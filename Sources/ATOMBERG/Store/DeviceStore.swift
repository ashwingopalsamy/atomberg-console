import Foundation
import Observation
import OSLog

/// The store's current problem. The popover words most kinds itself; `message` is the store's sentence.
struct StoreIssue: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case keychain, credentials, developerMode, localNetwork, network, quotaExhausted, quotaReserved, other

        /// The user must act. Drives the orange glyph and the menu bar badge.
        var needsAction: Bool {
            switch self {
            case .keychain, .credentials, .developerMode, .localNetwork: true
            default: false
            }
        }
    }

    let kind: Kind
    let message: String
}

/// Why local control is on but no fan answers.
enum LANProblem: Equatable, Sendable {
    /// macOS refused local network traffic: the permission is off for this build.
    case blocked
    /// Traffic is allowed, but no fan is on this network segment.
    case silent
}

@MainActor
@Observable
final class DeviceStore {
    private(set) var snapshots: [DeviceSnapshot] = []
    private(set) var links: [String: LinkState] = [:]
    private(set) var phases: [String: CommandPhase] = [:]
    private(set) var quota: QuotaStatus?
    private(set) var isConfigured = false
    private(set) var isRefreshing = false
    /// Local control is on and listening, yet no fan has been heard for a while.
    private(set) var lanProblem: LANProblem?
    /// A manual local check is running (`checkLocalNow`).
    private(set) var isCheckingLocal = false
    private(set) var lastError: StoreIssue?
    /// Mirrors settings.localControlEnabled so observers see the saved choice change.
    private(set) var localControlEnabled: Bool
    /// True only when the Keychain holds no credentials. A failed read never sets it.
    private(set) var needsOnboarding = false
    /// Set when a Keychain read fails. Cloud calls wait for Refresh, so calls do not read and prompt again.
    private(set) var keychainBlocked = false

    private let cloud: any CloudAPI
    private let lan: any LANControl
    private let ledger: any QuotaAccounting
    private let cache: any DeviceCaching
    private let credentials: any CredentialStoring
    private let settings: SettingsStore

    @ObservationIgnored private var lastCloudRead: Date?
    @ObservationIgnored private var catalogueListedAt: Date?
    @ObservationIgnored private var fanAnalyticsByID: [String: FanAnalytics] = [:]
    @ObservationIgnored private var purifierAnalyticsByID: [String: PurifierAnalytics] = [:]
    @ObservationIgnored private var lanRunning = false
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var lanEventTask: Task<Void, Never>?
    @ObservationIgnored private var linkTickerTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    // Callers that arrived mid-refresh. The follow-up refresh is forced if any of them asked for one.
    @ObservationIgnored private var reconcilePending = false
    @ObservationIgnored private var reconcileForceCatalogue = false
    @ObservationIgnored private var sendsInFlight: Set<String> = []
    // Commands waiting behind the one in flight, oldest first. A queue exists only while its device's drain runs.
    @ObservationIgnored private var waitingSends: [String: [Outgoing]] = [:]
    // Cloud commands the device has accepted but no report has shown yet. A report that arrives inside the window
    // and still shows the old value is stale, so it must not undo the optimistic value. No cloud read is made to
    // confirm: the fan's own UDP broadcast does that for free, and the next scheduled read settles the rest.
    @ObservationIgnored private var unconfirmed: [String: Unconfirmed] = [:]
    @ObservationIgnored private var analyticsReadAt: Date?
    @ObservationIgnored private var lanStartedAt: Date?

    private static let catalogueMaxAge: TimeInterval = 24 * 60 * 60
    private static let analyticsMaxAge: TimeInterval = 24 * 60 * 60
    /// Usage figures are the first thing to give up when the day's calls run low.
    private static let analyticsMinRemaining = 30
    private static let keychainReadFailure = "Couldn’t read your saved credentials from the Keychain. Allow Atomberg Console, then press Refresh."

    /// A command the store has accepted. `optimistic` is the reading the store showed once it was applied.
    private struct Outgoing {
        let command: DeviceCommand
        let optimistic: DeviceReading?
    }

    /// A cloud command awaiting confirmation. `lastRaw` is the device's last report, shown if the window ends first.
    private struct Unconfirmed {
        var commands: [DeviceCommand]
        var until: Date
        var lastRaw: DeviceReading?
    }

    // Commands that set the same value. A newer command with the same key supersedes a queued one.
    private enum CommandKey: Hashable {
        case power, speed, sleep, light, brightness, colour, timer
        case mode, idleSleep, sleepWindow

        init(_ command: DeviceCommand) {
            switch command {
            case .fan(.power): self = .power
            case .fan(.speed): self = .speed
            case .fan(.sleep): self = .sleep
            case .fan(.light): self = .light
            case .fan(.brightness): self = .brightness
            case .fan(.colour): self = .colour
            case .fan(.timerHours): self = .timer
            case .purifier(.mode): self = .mode
            case .purifier(.idleSleep): self = .idleSleep
            case .purifier(.sleepWindow), .purifier(.sleepWindowOff): self = .sleepWindow
            }
        }
    }

    init(cloud: any CloudAPI, lan: any LANControl, quota: any QuotaAccounting, cache: any DeviceCaching,
         credentials: any CredentialStoring, settings: SettingsStore) {
        self.cloud = cloud
        self.lan = lan
        self.ledger = quota
        self.cache = cache
        self.credentials = credentials
        self.settings = settings
        self.localControlEnabled = settings.localControlEnabled
    }

    // MARK: - Lifecycle

    // Safe on every launch. The Keychain read runs off the main actor, so a prompt cannot freeze the app.
    // Without saved credentials this only subscribes to LAN events and starts the link ticker.
    func start() async {
        localControlEnabled = settings.localControlEnabled
        // Subscribe before LAN can start, so an early beacon or state broadcast is not lost.
        observeLANEvents()
        startLinkTicker()
        guard !hasStarted else { return }

        // Listening needs no credentials. It must not wait behind a Keychain prompt, which after every rebuild
        // stays on screen until it is answered. A no-op when consent has already started LAN.
        if settings.localControlEnabled { startLANInBackground() }

        var readFailed = false
        if !isConfigured {
            do {
                // Existence only. The credentials themselves are read by the first cloud call that needs them, so
                // a Keychain prompt never stands between the user and the cached devices or local control.
                let saved = try await keychain { try $0.hasCredentials() }
                guard saved else {
                    needsOnboarding = true
                    return
                }
            } catch {
                // Only a missing item means no login. A failed read keeps the cache, and Refresh retries the read.
                readFailed = true
                keychainBlocked = true
                lastError = StoreIssue(kind: .keychain, message: Self.keychainReadFailure)
            }
            isConfigured = true
            if let cached = cache.load() {
                snapshots = Self.ordered(cached.devices)
                lastCloudRead = cached.savedAt
                catalogueListedAt = cached.savedAt
                analyticsReadAt = cached.analyticsAt
            }
            rebuildLinks(onLAN: [])
        }
        hasStarted = true
        Task { await refreshQuota() }
        if !readFailed { await refreshIfStale() }
    }

    // Refresh calls this while the Keychain is blocked. It is the only read after a failure.
    func retryKeychain() async {
        keychainBlocked = false
        do {
            _ = try await keychain { try $0.loadCredentials() }
        } catch {
            keychainBlocked = true
            lastError = StoreIssue(kind: .keychain, message: Self.keychainReadFailure)
            return
        }
        lastError = nil
        await refreshNow()
    }

    // A cloud read costs one of the day's 100 calls. Fans that are heard locally keep themselves current
    // over UDP, so a catalogue made only of such fans is read far less often.
    func refreshIfStale() async {
        let liveOnLAN = !snapshots.isEmpty && snapshots.allSatisfy { links[$0.id] == .local }
        let limit = liveOnLAN ? Timing.staleAfterOnLAN : Timing.staleAfter
        if let lastCloudRead, Date().timeIntervalSince(lastCloudRead) < limit { return }
        await refreshNow()
    }

    /// Usage figures change slowly and only the detail screens show them, so they are read when a detail
    /// screen opens, at most once every six hours.
    func refreshAnalyticsIfStale() async {
        guard isConfigured, !keychainBlocked, !snapshots.isEmpty else { return }
        if let quota, quota.remaining < Self.analyticsMinRemaining { return }
        let now = Date()
        if let analyticsReadAt, now.timeIntervalSince(analyticsReadAt) < Self.analyticsMaxAge { return }
        // Set first, so two detail screens opening together share one read.
        analyticsReadAt = now
        do {
            let analytics = try await cloudCall { try await cloud.readAnalytics() }
            fanAnalyticsByID = analytics.fans
            purifierAnalyticsByID = analytics.purifiers
            applyAnalytics()
            // The save time is the last state read, so an analytics read does not make the states look fresh.
            persist(at: lastCloudRead ?? now)
        } catch {
            // A read that was refused or never sent leaves the next open free to try again.
            analyticsReadAt = nil
            if !(error is CancellationError), Self.kind(for: error) != .quotaReserved {
                lastError = Self.issue(for: error)
            }
        }
    }

    /// Refresh pressed by the user. A blocked Keychain is retried instead, which then refreshes.
    func refreshFromUser() async {
        if keychainBlocked {
            await retryKeychain()
        } else {
            await refreshNow()
        }
    }

    /// The home list: one group per kind, the busiest devices first inside each. See `DeviceOrder`.
    var deviceGroups: [DeviceOrder.Group] { DeviceOrder.groups(snapshots, links: links) }

    /// The speed of a fan that is on and reachable, otherwise nil. Only such a fan counts as running or spins.
    func runningSpeed(of id: String) -> Int? {
        guard let link = links[id], link != .offline,
              let snapshot = snapshots.first(where: { $0.id == id }),
              case .fan(let state)? = snapshot.reading, state.power else { return nil }
        return state.speed
    }

    // Re-lists devices when forced, when there are none, or when the last listing is over a day old.
    // A caller that arrives mid-refresh does not start its own. It marks a follow-up that the running task
    // performs after the current refresh, so the request is not lost. Such callers share one follow-up.
    func refreshNow(forceCatalogue: Bool = false) async {
        guard isConfigured else { return }
        if let running = refreshTask {
            reconcilePending = true
            reconcileForceCatalogue = reconcileForceCatalogue || forceCatalogue
            await running.value
            return
        }
        let task = Task {
            await self.performRefresh(forceCatalogue: forceCatalogue)
            // A request that arrives during a follow-up sets the flag again, so the loop serves it too.
            while self.reconcilePending {
                let force = self.reconcileForceCatalogue
                self.reconcilePending = false
                self.reconcileForceCatalogue = false
                await self.performRefresh(forceCatalogue: force)
            }
            self.refreshTask = nil
            self.isRefreshing = false
        }
        refreshTask = task
        isRefreshing = true
        // A caller that is cancelled (popover closed mid-refresh) stops the refresh before its next call.
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Commands

    func send(_ command: DeviceCommand, to deviceID: String) async {
        guard let snapshot = snapshots.first(where: { $0.id == deviceID }) else { return }
        let current = snapshot.reading
        let optimistic = current.flatMap { OptimisticReducer.apply(command, to: $0) }
        // Nothing would acknowledge a command that changes nothing, so sending it would only spend a call.
        if let optimistic, optimistic == current { return }
        if let optimistic { store(optimistic, for: deviceID, at: nil) }
        let outgoing = Outgoing(command: command, optimistic: optimistic)

        // One send in flight per device. Later commands queue behind it.
        if sendsInFlight.contains(deviceID) {
            enqueue(outgoing, for: deviceID)
            return
        }
        sendsInFlight.insert(deviceID)
        phases[deviceID] = .pending(since: Date())
        // Unstructured, so cancelling the caller cannot strand an applied command that never reaches the device.
        await Task { await self.drain(outgoing, baseline: current, for: deviceID) }.value
    }

    func requestGuestPin(for deviceID: String) async throws -> GuestPin {
        // G1 ignores the window and SL1 requires it, so one window serves every lock.
        let window = DateInterval(start: Date(), duration: 900)
        return try await cloudCall { try await cloud.guestPin(for: deviceID, window: window) }
    }

    // MARK: - Onboarding and local control

    func connect(apiKey: String, refreshToken: String,
                 onStage: (ConnectStage) -> Void = { _ in }) async throws {
        let pair = Credentials(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            refreshToken: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !pair.apiKey.isEmpty, !pair.refreshToken.isEmpty else { throw CloudError.invalidCredentials }
        // Replacing credentials is a user action, so it may read the Keychain again.
        keychainBlocked = false

        // Nothing is stored until the key is proven, so a wrong key never persists.
        onStage(.credentials)
        let token = try await cloudCall { try await cloud.fetchAccessToken(credentials: pair) }
        // Read what is stored before overwriting it, so a failed replacement can restore a working login.
        let previous: Credentials? = try await readBeforeReplace { try $0.loadCredentials() }
        let previousToken: AccessToken? = try await readBeforeReplace { try $0.loadAccessToken() }
        try await keychain { try $0.saveCredentials(pair) }
        do {
            try await keychain { try $0.saveAccessToken(token) }
            onStage(.devices)
            let now = Date()
            let devices = try await cloudCall { try await cloud.listDevices() }
            onStage(.status)
            let readings = try await cloudCall { try await cloud.readStates(deviceIDs: []) }
            adopt(devices)
            catalogueListedAt = now
            mergeReadings(readings, at: now)
            lastCloudRead = now
            persist(at: now)
        } catch {
            await restoreCredentials(previous, token: previousToken)
            throw error
        }
        isConfigured = true
        needsOnboarding = false
        lastError = nil
        // LAN is not started here. Its prompt belongs to the consent step, which calls setLocalControl.
        await recomputeLinks()
    }

    // Puts back what connect replaced. A stored pair is overwritten in place, so a failed write cannot leave the
    // Keychain empty. Only a first pair, which never worked, is deleted.
    private func restoreCredentials(_ previous: Credentials?, token: AccessToken?) async {
        guard let previous else {
            _ = try? await keychain { try $0.deleteCredentials() }
            return
        }
        _ = try? await keychain { try $0.saveCredentials(previous) }
        // The token that was just minted belongs to the replacement pair, so it must not outlive the restore.
        if let token {
            _ = try? await keychain { try $0.saveAccessToken(token) }
        } else {
            _ = try? await keychain { try $0.deleteAccessToken() }
        }
    }

    // Reports presence only. It never starts LAN, so the macOS prompt cannot appear before consent.
    func probeLocalNetwork(duration: Duration) async -> [String: LinkState] {
        var onLAN: Set<String> = []
        // With no listener no beacon can arrive, so waiting would only delay an answer that is already known.
        if lanRunning {
            try? await Task.sleep(for: duration)
            onLAN = await fanIDsOnLAN()
        }
        rebuildLinks(onLAN: onLAN)
        let fans = snapshots.filter { $0.info.kind == .fan }
        return Dictionary(
            fans.map { ($0.id, onLAN.contains($0.id) ? LinkState.local : LinkState.cloud) },
            uniquingKeysWith: { first, _ in first })
    }

    /// The manual check behind the header's wifi button. Turns local control on if it is off, looks for fans with a
    /// fresh socket, and reports the result at once instead of after the usual 20 s of silence.
    func checkLocalNow() async {
        guard !isCheckingLocal else { return }
        isCheckingLocal = true
        defer { isCheckingLocal = false }
        if !localControlEnabled {
            await setLocalControl(true)
        } else if !lanRunning {
            await startLAN()
        }
        _ = await lan.recheck()
        lanStartedAt = Date().addingTimeInterval(-Timing.lanSilenceGrace - 1)
        await recomputeLinks()
    }

    func setLocalControl(_ enabled: Bool) async {
        settings.localControlEnabled = enabled
        localControlEnabled = enabled
        if enabled { await startLAN() } else { await stopLAN() }
        await recomputeLinks()
    }

    func disconnect() throws {
        refreshTask?.cancel()
        unconfirmed = [:]
        analyticsReadAt = nil
        try credentials.deleteCredentials()
        cache.save(CatalogueCache(devices: [], savedAt: Date()))
        snapshots = []
        links = [:]
        phases = [:]
        quota = nil
        isConfigured = false
        hasStarted = false
        needsOnboarding = true
        keychainBlocked = false
        localControlEnabled = settings.localControlEnabled
        lastError = nil
        lastCloudRead = nil
        catalogueListedAt = nil
        fanAnalyticsByID = [:]
        purifierAnalyticsByID = [:]
        Task { await stopLAN() }
    }

    // MARK: - Local network

    // Resubscribes if the consumer has ended, in case the LAN layer finished its stream on stop().
    private func observeLANEvents() {
        guard lanEventTask == nil else { return }
        let events = lan.events()
        lanEventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
            self?.lanEventTask = nil
        }
    }

    private func handle(_ event: LANEvent) async {
        switch event {
        case .presence(let presence):
            if !snapshots.contains(where: { $0.id == presence.deviceID }) {
                Logger.lan.info("Presence for \(presence.deviceID, privacy: .public), which is not in the catalogue")
            }
            await refreshLink(for: presence.deviceID)
        case .state(let deviceID, let state):
            guard snapshots.contains(where: { $0.id == deviceID && $0.info.kind == .fan }) else { return }
            // A queued or in-flight send is newer than this broadcast, so storing it would flicker the value back.
            if !sendsInFlight.contains(deviceID) {
                let now = Date()
                store(settle(lanReading(state, for: deviceID, at: now), for: deviceID, at: now), for: deviceID, at: now)
            }
            await refreshLink(for: deviceID)
        }
    }

    private func startLANInBackground() {
        Task { await startLAN() }
    }

    private func startLAN() async {
        guard !lanRunning else { return }
        lanRunning = true
        observeLANEvents()
        do {
            try await lan.start()
            lanStartedAt = Date()
        } catch {
            lanRunning = false
            lastError = StoreIssue(kind: .localNetwork, message: "Local control couldn’t start. Check local network access in System Settings.")
        }
    }

    private func stopLAN() async {
        guard lanRunning else { return }
        lanRunning = false
        lanStartedAt = nil
        if lanProblem != nil { lanProblem = nil }
        await lan.stop()
        // Stop must not leave presence behind, or fans would keep showing Local with no listener.
        await lan.forgetAllPresence()
    }

    // The ticker holds self weakly so it ends with the store and never keeps it alive.
    private func startLinkTicker() {
        guard linkTickerTask == nil else { return }
        linkTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.recomputeLinks()
            }
        }
    }

    // MARK: - Links

    private func recomputeLinks() async {
        let onLAN = await fanIDsOnLAN()
        rebuildLinks(onLAN: onLAN)
        var problem: LANProblem?
        if lanRunning, let started = lanStartedAt,
           Date().timeIntervalSince(started) > Timing.lanSilenceGrace,
           snapshots.contains(where: { $0.info.kind == .fan }) {
            switch await lan.health() {
            case .heard: problem = nil
            case .silent: problem = .silent
            case .blocked: problem = .blocked
            }
        }
        // Assign only on change, so the once-a-second ticker does not wake observers.
        if lanProblem != problem { lanProblem = problem }
    }

    private func refreshLink(for id: String) async {
        let presence = await lan.presence(of: id)
        guard let snapshot = snapshots.first(where: { $0.id == id }) else { return }
        setLink(Self.link(for: snapshot, onLAN: presence != nil), for: id)
    }

    private func fanIDsOnLAN() async -> Set<String> {
        var ids: Set<String> = []
        for snapshot in snapshots where snapshot.info.kind == .fan {
            let presence = await lan.presence(of: snapshot.id)
            if presence != nil { ids.insert(snapshot.id) }
        }
        return ids
    }

    private func rebuildLinks(onLAN: Set<String>) {
        let updated = Dictionary(
            snapshots.map { ($0.id, Self.link(for: $0, onLAN: onLAN.contains($0.id))) },
            uniquingKeysWith: { first, _ in first })
        // Assign only on change, so the once-a-second ticker does not wake observers.
        if links != updated { links = updated }
    }

    private func setLink(_ value: LinkState, for id: String) {
        if links[id] != value { links[id] = value }
    }

    private static func link(for snapshot: DeviceSnapshot, onLAN: Bool) -> LinkState {
        if snapshot.info.kind == .fan, onLAN { return .local }
        guard let reading = snapshot.reading else { return .offline }
        let isOnline: Bool
        switch reading {
        case .fan(let state): isOnline = state.isOnline
        case .purifier(let state): isOnline = state.isOnline
        case .lock(let state): isOnline = state.isOnline
        }
        return isOnline ? .cloud : .offline
    }

    // MARK: - Snapshot merging

    // Keeps each device's last reading, so a relisting whose state read then fails does not blank the popover.
    private func adopt(_ devices: [DeviceInfo]) {
        let known = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        snapshots = Self.ordered(devices.map { info in
            var snapshot = known[info.id] ?? DeviceSnapshot(
                info: info, reading: nil, fanAnalytics: nil, purifierAnalytics: nil, lastUpdated: nil)
            snapshot.info = info
            snapshot.fanAnalytics = fanAnalyticsByID[info.id]
            snapshot.purifierAnalytics = purifierAnalyticsByID[info.id]
            return snapshot
        })
    }

    // A LAN reading newer than the cloud's report wins, so a slower cloud read cannot undo a newer local state.
    private func mergeReadings(_ readings: [String: DeviceReading], at now: Date) {
        for index in snapshots.indices {
            // A read can predate an in-flight or queued send. A queue exists only while its drain runs, so this covers both.
            let id = snapshots[index].id
            guard !sendsInFlight.contains(id), let fresh = readings[id] else { continue }
            if let current = snapshots[index].reading, Self.isLANReading(current),
               let observed = snapshots[index].lastUpdated,
               observed > (Self.reportedAt(of: fresh) ?? now) {
                continue
            }
            snapshots[index].reading = settle(fresh, for: id, at: now)
            snapshots[index].lastUpdated = now
        }
    }

    private func applyAnalytics() {
        for index in snapshots.indices {
            snapshots[index].fanAnalytics = fanAnalyticsByID[snapshots[index].id]
            snapshots[index].purifierAnalytics = purifierAnalyticsByID[snapshots[index].id]
        }
    }

    private func store(_ reading: DeviceReading, for id: String, at observed: Date?) {
        guard let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[index].reading = reading
        if let observed { snapshots[index].lastUpdated = observed }
    }

    private func reading(for id: String) -> DeviceReading? {
        snapshots.first(where: { $0.id == id })?.reading
    }

    private func persist(at date: Date) {
        cache.save(CatalogueCache(devices: snapshots, savedAt: date, analyticsAt: analyticsReadAt))
    }

    // MARK: - Refresh

    // One call for the states of every device. The catalogue is listed only when there is none or it is a day old,
    // and usage figures are read separately (`refreshAnalyticsIfStale`), so a refresh costs one call.
    private func performRefresh(forceCatalogue: Bool) async {
        let now = Date()
        do {
            if forceCatalogue || snapshots.isEmpty || catalogueIsStale(at: now) {
                let devices = try await cloudCall { try await cloud.listDevices() }
                adopt(devices)
                catalogueListedAt = now
            }
            let readings = try await cloudCall { try await cloud.readStates(deviceIDs: []) }
            mergeReadings(readings, at: now)
            lastCloudRead = now
            lastError = nil
            persist(at: now)
        } catch {
            // A refresh cancelled because the popover closed is not a failure to show.
            if !(error is CancellationError) { lastError = Self.issue(for: error) }
        }
        await recomputeLinks()
    }

    // The listing date is not persisted. A launch counts the cache's save time as the listing, so only a catalogue
    // that was not saved for a day is listed again.
    private func catalogueIsStale(at now: Date) -> Bool {
        guard let catalogueListedAt else { return true }
        return now.timeIntervalSince(catalogueListedAt) > Self.catalogueMaxAge
    }

    // MARK: - Command delivery

    // A newer command with the same key takes the queued one's place. Everything else keeps its order.
    // The new command goes last, not into the superseded slot, so the device sees commands in the order
    // the optimistic reading applied them.
    private func enqueue(_ outgoing: Outgoing, for deviceID: String) {
        let key = CommandKey(outgoing.command)
        var queue = waitingSends[deviceID, default: []]
        queue.removeAll { CommandKey($0.command) == key }
        queue.append(outgoing)
        waitingSends[deviceID] = queue
    }

    private func dequeue(for deviceID: String) -> Outgoing? {
        guard var queue = waitingSends.removeValue(forKey: deviceID), !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        if !queue.isEmpty { waitingSends[deviceID] = queue }
        return next
    }

    // A failure stays visible until its drain ends. Successes later in the same drain must not overwrite it.
    private func setPhase(_ phase: CommandPhase, for deviceID: String) {
        if case .failed? = phases[deviceID] { return }
        phases[deviceID] = phase
    }

    // Runs the device's queue until it is empty. Only one drain exists per device at a time.
    private func drain(_ first: Outgoing, baseline: DeviceReading?, for deviceID: String) async {
        var outgoing = first
        var rollbackTarget = baseline
        var failedWithQueue = false
        while true {
            // A failed command leaves the device where it was, so only a delivered one moves the rollback point.
            let delivered = await dispatch(outgoing, rollbackTo: rollbackTarget, for: deviceID)
            if delivered, let applied = outgoing.optimistic {
                rollbackTarget = applied
            }
            if !delivered, waitingSends[deviceID] != nil { failedWithQueue = true }
            guard let next = dequeue(for: deviceID) else { break }
            setPhase(.pending(since: Date()), for: deviceID)
            outgoing = next
        }
        sendsInFlight.remove(deviceID)
        scheduleFailureClear(for: deviceID)
        // An accepted command is done: the API answered 2xx, and no read is spent to check it.
        if case .pending? = phases[deviceID] {
            phases[deviceID] = .idle
        }
        // Broadcasts were dropped during the drain, so a failed queue is read back in full.
        if failedWithQueue { await refreshNow() }
    }

    // Sends one command by LAN when it can, otherwise by cloud. Returns true when the device accepted it.
    private func dispatch(_ outgoing: Outgoing, rollbackTo previous: DeviceReading?,
                          for deviceID: String) async -> Bool {
        guard let kind = snapshots.first(where: { $0.id == deviceID })?.info.kind else { return false }
        let status = await ledger.status()
        quota = status
        var lanPresent = false
        if case .fan = outgoing.command {
            lanPresent = await lan.presence(of: deviceID) != nil
        }

        switch Routing.route(for: outgoing.command, kind: kind, lanPresent: lanPresent, quota: status) {
        case .lan:
            if case .fan(let fan) = outgoing.command,
               case .acknowledged(let state) = await lan.send(fan, to: deviceID) {
                // A queued command is newer than this ack. Storing the ack would flicker the UI back to an older value.
                if waitingSends[deviceID] == nil {
                    let now = Date()
                    store(lanReading(state, for: deviceID, at: now), for: deviceID, at: now)
                }
                setPhase(.idle, for: deviceID)
                setLink(.local, for: deviceID)
                return true
            }
            guard Routing.cloudAllowed(status) else {
                fail(deviceID, previous: previous, optimistic: outgoing.optimistic, message: "Didn’t reach the fan.")
                return false
            }
            return await sendToCloud(outgoing, to: deviceID, rollbackTo: previous)
        case .cloud:
            return await sendToCloud(outgoing, to: deviceID, rollbackTo: previous)
        case .unavailable(let reason):
            fail(deviceID, previous: previous, optimistic: outgoing.optimistic, message: reason)
            return false
        }
    }

    private func sendToCloud(_ outgoing: Outgoing, to deviceID: String,
                             rollbackTo previous: DeviceReading?) async -> Bool {
        do {
            try await cloudCall { try await cloud.send(outgoing.command, to: deviceID) }
            recordUnconfirmed(outgoing.command, for: deviceID, baseline: previous)
            return true
        } catch CloudError.gatewayTimeout {
            // A timeout does not say whether the command applied. Reading the state back would be a second call for
            // every slow answer, so the optimistic value stays and the next scheduled read, or a broadcast, settles it.
            recordUnconfirmed(outgoing.command, for: deviceID, baseline: previous)
            return true
        } catch {
            fail(deviceID, previous: previous, optimistic: outgoing.optimistic, message: Self.sentence(for: error))
            return false
        }
    }

    private func fail(_ deviceID: String, previous: DeviceReading?, optimistic: DeviceReading?, message: String) {
        // Roll back only if nothing newer has replaced our optimistic value. A LAN broadcast or a
        // queued command may have arrived meanwhile.
        if let previous, let optimistic, reading(for: deviceID) == optimistic {
            store(previous, for: deviceID, at: nil)
        }
        phases[deviceID] = .failed(message: message, at: Date())
    }

    // Called once the drain that produced the failure has ended. The message stays 10 seconds after that,
    // unless a newer result has replaced it.
    private func scheduleFailureClear(for deviceID: String) {
        guard case .failed(_, let failedAt)? = phases[deviceID] else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, case .failed(_, let at)? = self.phases[deviceID], at == failedAt else { return }
            self.phases[deviceID] = .idle
        }
    }

    // MARK: - Confirmation

    // Records an accepted cloud command. Until a report confirms it, its device shows the optimistic value.
    private func recordUnconfirmed(_ command: DeviceCommand, for deviceID: String, baseline: DeviceReading?) {
        let until = Date().addingTimeInterval(Timing.cloudSettleWindow)
        var entry = unconfirmed[deviceID] ?? Unconfirmed(commands: [], until: until, lastRaw: baseline)
        entry.commands.append(command)
        entry.until = until
        unconfirmed[deviceID] = entry
    }

    // Decides what a device report shows while a command is unconfirmed. A report that already has the commands
    // applied confirms them. Any other report keeps the optimistic value, which an older report cannot overturn.
    private func settle(_ fresh: DeviceReading, for deviceID: String, at now: Date) -> DeviceReading {
        guard var entry = unconfirmed[deviceID] else { return fresh }
        let baseline = entry.lastRaw
        entry.lastRaw = fresh
        let expected = entry.commands.reduce(fresh) { OptimisticReducer.apply($1, to: $0) ?? $0 }
        if Self.confirms(fresh, expected: expected, baseline: baseline) {
            unconfirmed[deviceID] = nil
            if case .pending? = phases[deviceID], !sendsInFlight.contains(deviceID) {
                phases[deviceID] = .idle
            }
            return fresh
        }
        // The window ended without a matching report, so the device's own report is the truth.
        if now >= entry.until {
            unconfirmed[deviceID] = nil
            return fresh
        }
        unconfirmed[deviceID] = entry
        return expected
    }

    // The device quantises brightness and timer, so their echo need not equal the command. A brightness counts when it
    // moved from the baseline toward the commanded value and lies within 5 points of it. A timer counts on any change.
    // Every other field must still match exactly.
    private static func confirms(_ fresh: DeviceReading, expected: DeviceReading, baseline: DeviceReading?) -> Bool {
        if expected == fresh { return true }
        guard case .fan(var tolerated) = expected, case .fan(let report) = fresh else { return false }
        var base: FanState?
        if case .fan(let state)? = baseline { base = state }
        if let commanded = tolerated.brightness, let shown = report.brightness,
           brightnessMoved(from: base?.brightness, to: shown, toward: commanded) {
            tolerated.brightness = shown
        }
        if let base, base.timerHours != report.timerHours {
            tolerated.timerHours = report.timerHours
        }
        return .fan(tolerated) == fresh
    }

    private static func brightnessMoved(from before: Int?, to shown: Int, toward commanded: Int) -> Bool {
        let gap = abs(shown - commanded)
        guard gap <= 5 else { return false }
        guard let before else { return true }
        return gap < abs(before - commanded)
    }

    // MARK: - Cloud plumbing

    // Quota is refreshed after failed attempts too, because the ledger counts them.
    private func cloudCall<T: Sendable>(_ call: () async throws -> T) async throws -> T {
        // A cancelled refresh must not spend another call.
        try Task.checkCancellation()
        // The cloud client reads the Keychain on every call, so after a failed read each call would prompt again.
        if keychainBlocked { throw KeychainError.unavailable }
        do {
            let value = try await call()
            await refreshQuota()
            return value
        } catch {
            if error is KeychainError { keychainBlocked = true }
            await refreshQuota()
            throw error
        }
    }

    // Keychain calls can show a system prompt and block their thread, so they run off the main actor.
    private func keychain<T: Sendable>(
        _ operation: @escaping @Sendable (any CredentialStoring) throws -> T
    ) async throws -> T {
        let store = credentials
        do {
            return try await Task.detached { try operation(store) }.value
        } catch let error as KeychainError {
            keychainBlocked = true
            throw error
        }
    }

    // An item that no longer decodes must not block its own replacement, so it counts as absent here.
    private func readBeforeReplace<T: Sendable>(
        _ read: @escaping @Sendable (any CredentialStoring) throws -> T?
    ) async throws -> T? {
        do {
            return try await keychain(read)
        } catch is DecodingError {
            return nil
        }
    }

    private func refreshQuota() async {
        quota = await ledger.status()
    }

    // MARK: - Pure helpers

    // A LAN broadcast reports brightness and colour as nil when their bits are 0. That means no reading, not no light,
    // so the last known values are kept and the light controls stay visible.
    private func lanReading(_ state: FanState, for deviceID: String, at date: Date) -> DeviceReading {
        var state = state
        if case .fan(let previous)? = reading(for: deviceID) {
            state.brightness = state.brightness ?? previous.brightness
            state.colour = state.colour ?? previous.colour
        }
        state.source = .lan
        // A broadcast proves the fan is online, so the link rule can keep reading isOnline.
        state.isOnline = true
        state.reportedAt = date
        return .fan(state)
    }

    private static func isLANReading(_ reading: DeviceReading) -> Bool {
        if case .fan(let state) = reading { return state.source == .lan }
        return false
    }

    private static func reportedAt(of reading: DeviceReading) -> Date? {
        switch reading {
        case .fan(let state): return state.reportedAt
        case .purifier(let state): return state.reportedAt
        case .lock(let state): return state.reportedAt
        }
    }

    private static func ordered(_ snapshots: [DeviceSnapshot]) -> [DeviceSnapshot] {
        snapshots.sorted { lhs, rhs in
            let leftRank = rank(lhs.info.kind)
            let rightRank = rank(rhs.info.kind)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.info.name.localizedStandardCompare(rhs.info.name) == .orderedAscending
        }
    }

    private static func rank(_ kind: DeviceKind) -> Int {
        switch kind {
        case .fan: return 0
        case .waterPurifier: return 1
        case .lock: return 2
        }
    }

    private static func issue(for error: Error) -> StoreIssue {
        StoreIssue(kind: kind(for: error), message: sentence(for: error))
    }

    private static func kind(for error: Error) -> StoreIssue.Kind {
        if error is KeychainError { return .keychain }
        guard let cloudError = error as? CloudError else { return .other }
        switch cloudError {
        case .quotaReserved: return .quotaReserved
        case .quotaExhausted: return .quotaExhausted
        case .invalidCredentials: return .credentials
        case .developerModeOff: return .developerMode
        case .network: return .network
        default: return .other
        }
    }

    private static func sentence(for error: Error) -> String {
        if error is KeychainError { return keychainReadFailure }
        guard let cloudError = error as? CloudError else { return "ATOMBERG didn’t answer. Try again." }
        switch cloudError {
        case .quotaReserved:
            return "Cloud reads are paused to keep \(QuotaPolicy.reserve) calls for commands."
        case .quotaExhausted:
            return "You’ve used today’s \(QuotaPolicy.dailyLimit) cloud calls. They reset \(QuotaStatus.nextResetPhrase())."
        case .invalidCredentials:
            return "ATOMBERG rejected the credentials. Replace them from the menu bar."
        case .developerModeOff:
            return "Developer Mode is off in the Atomberg Home app."
        case .network:
            return "No connection to ATOMBERG."
        case .deviceOffline:
            return "Device is offline."
        default:
            return "ATOMBERG didn’t answer. Try again."
        }
    }
}
