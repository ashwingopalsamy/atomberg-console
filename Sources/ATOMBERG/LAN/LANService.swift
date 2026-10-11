import Dispatch
import Foundation
import OSLog

extension Logger {
    static let lan = Logger(subsystem: "com.ashwin.ATOMBERG", category: "lan")
}

/// Local control for fans. Beacons and state broadcasts arrive on UDP 5625, commands leave on UDP 5600.
actor LANService: LANControl {
    private static let listenPort: UInt16 = 5625
    private static let commandPort: UInt16 = 5600
    private static let probe = Data("ATOMBERG-CONSOLE-PROBE".utf8)
    /// While no fan has been heard, the probe is sent again this often, so a permission granted after launch is seen.
    private static let probeInterval: TimeInterval = 15

    /// Created by a device's first beacon. State broadcasts from devices without one are ignored.
    private struct Device {
        var address: String
        var series: String?
        /// nil after `stop()` or `forgetAllPresence()`, until the next beacon or state broadcast.
        var lastSeen: Date?
        var lastState: FanState?
    }

    private struct Waiter {
        let deviceID: String
        let command: FanCommand
        let continuation: CheckedContinuation<FanState?, Never>
    }

    private nonisolated let hub = LANEventHub()
    private let readQueue = DispatchQueue(label: "atomberg.lan.receive")
    private var readSource: DispatchSourceRead?
    private var datagramSink: AsyncStream<ReceivedDatagram>.Continuation?
    private var pathWatcher: PathWatcher?
    private var devices: [String: Device] = [:]
    private var recentMessages = RecentKeys(capacity: 64)
    private var waiters: [UUID: Waiter] = [:]
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    /// Set by the first beacon or state broadcast. Our own probe and unrelated traffic never set it.
    private var heardFans = false
    private var probeRefused = false
    private var probeTask: Task<Void, Never>?

    func start() async throws {
        guard readSource == nil else { return }
        try openListener()
        heardFans = false
        probeRefused = false

        let watcher = PathWatcher { [weak self] in
            Task { await self?.pathChanged() }
        }
        watcher.start()
        pathWatcher = watcher

        sendProbe()
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.probeInterval))
                guard !Task.isCancelled else { return }
                await self?.probeIfSilent()
            }
        }
    }

    /// Binds UDP 5625 and starts reading. Used at start and again when the permission becomes effective.
    private func openListener() throws {
        let fd: Int32
        do {
            fd = try openReceiver(port: Self.listenPort)
        } catch {
            Logger.lan.info("Listener failed on UDP \(Self.listenPort, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
        Logger.lan.info("Listening on UDP \(Self.listenPort, privacy: .public)")
        let (datagrams, sink) = AsyncStream.makeStream(of: ReceivedDatagram.self)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        source.setEventHandler {
            for datagram in receiveAvailable(on: fd) {
                sink.yield(datagram)
            }
        }
        // Closing in the cancel handler keeps the descriptor valid for a read that is still running.
        source.setCancelHandler { closeSocket(fd) }
        source.resume()
        readSource = source
        datagramSink = sink

        // One stream keeps arrival order. A Task per datagram would let an older state overtake a newer one.
        Task { [weak self] in
            for await datagram in datagrams {
                await self?.handle(datagram)
            }
        }
    }

    /// A socket opened while macOS was still refusing this build (a new binary is checked against the Local
    /// Network preference on its first send, and that first send fails) stays deaf after the permission is
    /// effective. Opening a new one is what makes it hear.
    private func reopenListener() {
        guard readSource != nil else { return }
        readSource?.cancel()
        readSource = nil
        datagramSink?.finish()
        datagramSink = nil
        do {
            try openListener()
            Logger.lan.info("Listener reopened after the permission became effective")
        } catch {
            probeRefused = true
        }
    }

    /// macOS registers an app for Local Network privacy when it sends to the local network, and a listener that
    /// never sends can stay silently blocked without ever being asked. One broadcast makes the prompt appear.
    /// It is not a beacon or a state, so every listener on the port, this one included, discards it.
    /// The result is kept: a refused send is how a missing permission shows, and a later success clears it.
    private func sendProbe() {
        let wasRefused = probeRefused
        do {
            try sendDatagram(Self.probe, to: "255.255.255.255", port: Self.listenPort, broadcast: true)
            probeRefused = false
            if wasRefused { reopenListener() }
        } catch {
            probeRefused = true
            Logger.lan.info("Probe broadcast failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func probeIfSilent() {
        guard readSource != nil, !heardFans else { return }
        sendProbe()
    }

    private func pathChanged() {
        clearPresence()
        probeIfSilent()
    }

    /// Event streams stay open across stop and start, so the consumer does not need to resubscribe.
    func stop() async {
        probeTask?.cancel()
        probeTask = nil
        readSource?.cancel()
        readSource = nil
        datagramSink?.finish()
        datagramSink = nil
        pathWatcher?.stop()
        pathWatcher = nil
        clearPresence()
    }

    func forgetAllPresence() async {
        clearPresence()
    }

    func health() async -> LANHealth {
        if heardFans { return .heard }
        return probeRefused ? .blocked : .silent
    }

    func recheck() async -> LANHealth {
        guard readSource != nil else { return .silent }
        clearPresence()
        heardFans = false
        probeRefused = false
        // A fresh socket is the one that is sure to be subject to the permission as it stands now.
        reopenListener()
        sendProbe()
        let deadline = Date().addingTimeInterval(Timing.lanRecheckWindow)
        // Suspension points let the read stream deliver beacons, which is what sets `heardFans`.
        while Date() < deadline, !heardFans {
            try? await Task.sleep(for: .milliseconds(150))
        }
        return await health()
    }

    nonisolated func events() -> AsyncStream<LANEvent> {
        hub.subscribe()
    }

    func presence(of deviceID: String) async -> LANPresence? {
        livePresence(of: deviceID, at: Date())
    }

    func send(_ command: FanCommand, to deviceID: String) async -> LANSendResult {
        let data = command.commandData()
        for attempt in 1...2 {
            guard let presence = livePresence(of: deviceID, at: Date()) else {
                return attempt == 1 ? .notPresent : .noAcknowledgement
            }
            do {
                try sendDatagram(data, to: presence.address, port: Self.commandPort)
            } catch {
                return .noAcknowledgement
            }
            // No suspension separates the send from the waiter's registration, so a reply cannot be processed in between.
            if let state = await awaitAcknowledgement(of: command, from: deviceID, timeout: Timing.lanAckTimeout) {
                return .acknowledged(state)
            }
        }
        return .noAcknowledgement
    }

    // MARK: - Inbound datagrams

    private func handle(_ datagram: ReceivedDatagram) {
        guard readSource != nil else { return }
        let now = Date()
        if let beacon = Self.parseBeacon(datagram.payload) {
            markSeen(beacon.deviceID, address: datagram.sender, series: beacon.series, now: now)
        } else if let broadcast = StateDecoder.parseBroadcast(datagram.payload) {
            accept(broadcast, from: datagram.sender, now: now)
        } else {
            let head = datagram.payload.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
            Logger.lan.debug("Rejected datagram from \(datagram.sender, privacy: .public), \(datagram.payload.count, privacy: .public) bytes: \(head, privacy: .public)")
        }
    }

    private func accept(_ broadcast: StateDecoder.Broadcast, from address: String, now: Date) {
        let deviceID = broadcast.deviceID.lowercased()
        // A state broadcast proves presence as well as a beacon does, and carries the same sender address.
        markSeen(deviceID, address: address, series: nil, now: now)
        guard let known = devices[deviceID] else { return }
        guard recentMessages.insertIfNew("\(deviceID)/\(broadcast.messageID)") else { return }
        guard let state = StateDecoder.decode(
            stateString: broadcast.stateString,
            previousSpeed: known.lastState?.speed,
            series: known.series
        ) else { return }
        devices[deviceID]?.lastState = state
        hub.publish(.state(deviceID: deviceID, state))
        resolveWaiters(for: deviceID, with: state)
    }

    /// Publishes presence on a transition to present (including a return after the window lapsed) and on an address change.
    private func markSeen(_ deviceID: String, address: String, series: String?, now: Date) {
        if !heardFans {
            heardFans = true
            Logger.lan.info("First fan heard: \(deviceID, privacy: .public) at \(address, privacy: .public)")
        }
        let wasPresent = livePresence(of: deviceID, at: now) != nil
        var device = devices[deviceID] ?? Device(address: address, series: series, lastSeen: nil, lastState: nil)
        let moved = device.address != address
        device.address = address
        device.series = series ?? device.series
        device.lastSeen = now
        devices[deviceID] = device
        if !wasPresent || moved {
            hub.publish(.presence(LANPresence(deviceID: deviceID, address: address, lastSeen: now)))
        }
    }

    private func livePresence(of deviceID: String, at now: Date) -> LANPresence? {
        guard let device = devices[deviceID], let lastSeen = device.lastSeen,
              now.timeIntervalSince(lastSeen) <= Timing.lanPresenceWindow else { return nil }
        return LANPresence(deviceID: deviceID, address: device.address, lastSeen: lastSeen)
    }

    private func clearPresence() {
        for deviceID in devices.keys {
            devices[deviceID]?.lastSeen = nil
        }
    }

    /// A beacon is at most 15 bytes: the device's 12-character MAC, then an optional series.
    private static func parseBeacon(_ datagram: Data) -> (deviceID: String, series: String?)? {
        guard (12...15).contains(datagram.count) else { return nil }
        let mac = datagram.prefix(12).map { (0x41...0x46).contains($0) ? $0 + 0x20 : $0 }
        guard mac.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else { return nil }
        let trailing = String(decoding: datagram.dropFirst(12), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        let series: String? = trailing.isEmpty ? nil : trailing
        return (String(decoding: mac, as: UTF8.self), series)
    }

    // MARK: - Command acknowledgement

    private func awaitAcknowledgement(of command: FanCommand, from deviceID: String, timeout: TimeInterval) async -> FanState? {
        let id = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<FanState?, Never>) in
            waiters[id] = Waiter(deviceID: deviceID, command: command, continuation: continuation)
            timeouts[id] = Task {
                do {
                    try await Task.sleep(for: .seconds(timeout))
                } catch {
                    return
                }
                self.finishWaiter(id, with: nil)
            }
        }
    }

    private func resolveWaiters(for deviceID: String, with state: FanState) {
        let matched = waiters.filter { $0.value.deviceID == deviceID && Self.isSatisfied($0.value.command, by: state) }
        for id in matched.keys {
            finishWaiter(id, with: state)
        }
    }

    /// Removing the waiter first means only one of a match or a timeout can resume its continuation.
    private func finishWaiter(_ id: UUID, with state: FanState?) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        waiter.continuation.resume(returning: state)
    }

    private static func isSatisfied(_ command: FanCommand, by state: FanState) -> Bool {
        switch command {
        case .power(let on): return state.power == on
        case .speed(let level): return state.speed == level
        case .sleep(let on): return state.sleep == on
        case .light(let on): return state.light == on
        case .brightness(let percent): return state.brightness == percent
        case .colour(let colour): return state.colour == colour
        case .timerHours(let hours): return state.timerHours == hours
        }
    }
}

/// Least recently used message keys, for dropping repeats of one broadcast.
private struct RecentKeys {
    private let capacity: Int
    private var order: [String] = []
    private var members: Set<String> = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    /// Returns true if `key` was not already present. A repeat moves the key to the most recent end.
    mutating func insertIfNew(_ key: String) -> Bool {
        if members.contains(key) {
            order.removeAll { $0 == key }
            order.append(key)
            return false
        }
        members.insert(key)
        order.append(key)
        if order.count > capacity {
            members.remove(order.removeFirst())
        }
        return true
    }
}

/// Fans events out to every open stream. A lock, not the actor, guards the subscribers so `events()` can be synchronous.
private final class LANEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<LANEvent>.Continuation] = [:]

    func subscribe() -> AsyncStream<LANEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: LANEvent.self, bufferingPolicy: .bufferingNewest(64))
        continuation.onTermination = { [weak self] _ in self?.unsubscribe(id) }
        lock.withLock { subscribers[id] = continuation }
        return stream
    }

    func publish(_ event: LANEvent) {
        lock.withLock {
            for continuation in subscribers.values {
                continuation.yield(event)
            }
        }
    }

    private func unsubscribe(_ id: UUID) {
        lock.withLock { subscribers[id] = nil }
    }
}
