// Shared vocabulary for every module. This file is the contract between parallel workstreams.
// Do not change a signature here without updating every consumer. Implement, don't redefine.

import Foundation

// MARK: - Timing and quota policy

enum Timing {
    /// Cloud reads older than this are refreshed when the popover opens. Every read is one of the day's 100 calls.
    static let staleAfter: TimeInterval = 7_200
    /// The same, when every device is a fan that is heard locally and so reports its own changes over UDP.
    static let staleAfterOnLAN: TimeInterval = 6 * 3_600
    /// How long local control may listen without hearing any fan before the popover says so.
    static let lanSilenceGrace: TimeInterval = 20
    /// How long a manual check waits for a beacon. Fans send one a second, so this is a few chances.
    static let lanRecheckWindow: TimeInterval = 3.5
    /// A LAN beacon counts as present for this long after it was last seen.
    static let lanPresenceWindow: TimeInterval = 5
    /// How long a LAN command waits for the fan's state broadcast before it is resent or abandoned.
    static let lanAckTimeout: TimeInterval = 1.5
    /// Minimum gap between cloud calls (the API allows 5 per second).
    static let cloudMinimumGap: TimeInterval = 0.21
    /// Access tokens are refreshed when fewer than this many seconds remain.
    static let accessTokenRefreshMargin: TimeInterval = 3600
    /// A report this soon after an accepted cloud command that still shows the old value is treated as stale.
    static let cloudSettleWindow: TimeInterval = 10
}

enum QuotaPolicy {
    static let dailyLimit = 100
    /// Background reads never spend the last `reserve` calls. Token refresh and user actions may.
    static let reserve = 20
}

// MARK: - Device catalogue (from GET /get_list_of_devices)

enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case fan = "fan"
    case waterPurifier = "water_purifier"
    case lock = "lock"
}

struct SupportedCommand: Codable, Sendable, Equatable {
    let command: String
    let accepts: String
    let requires: [String]
    let subKeyOf: String?
}

struct DeviceInfo: Codable, Sendable, Equatable, Identifiable {
    /// device_id: 12 lowercase hex characters. Also the MAC address that LAN beacons carry.
    let id: String
    var name: String
    var series: String
    var model: String?
    var room: String?
    var kind: DeviceKind
    var supportedCommands: [SupportedCommand]
    /// The Wi-Fi network the device joined (`metadata.ssid`). Nil until a listing that carries it.
    var ssid: String? = nil
}

// MARK: - Readings

enum LightColour: String, Codable, Sendable, CaseIterable {
    case warm, cool, daylight
}

enum ReadingSource: String, Codable, Sendable {
    case lan, cloud
}

struct FanState: Codable, Sendable, Equatable {
    var power: Bool
    /// 1...6. Retained while the fan is off (the API calls this last_recorded_speed).
    var speed: Int
    var sleep: Bool
    var light: Bool
    /// 10...100 where the series has a light; nil otherwise.
    var brightness: Int?
    var colour: LightColour?
    /// 0 when no timer is running; otherwise 1, 2, 3 or 6.
    var timerHours: Int
    var timerElapsedMinutes: Int
    var isOnline: Bool
    var source: ReadingSource
    var reportedAt: Date?
}

enum PurifierMode: Int, Codable, Sendable, CaseIterable {
    case roOnly = 0
    case adaptive = 1
    case tasteTune50to100 = 2
    case tasteTune75to125 = 3
    case tasteTune100to150 = 4
    case vacay = 10

    var label: String {
        switch self {
        case .roOnly: "RO only"
        case .adaptive: "Adaptive"
        case .tasteTune50to100: "TasteTune 50–100"
        case .tasteTune75to125: "TasteTune 75–125"
        case .tasteTune100to150: "TasteTune 100–150"
        case .vacay: "Vacay"
        }
    }
}

struct PurifierState: Codable, Sendable, Equatable {
    var mode: PurifierMode?
    var inputTDS: Double?
    var storedTDS: Double?
    var idleSleep: Bool
    var sleepWindowOn: Bool
    var sleepStartUTC: UInt32?
    var sleepStopUTC: UInt32?
    /// Readable descriptions of every set fault bit. Empty when healthy.
    var faultDescriptions: [String]
    /// True when a filter stage is choked (the API's choking_faults.filter_choke).
    var filterChoked: Bool
    var isOnline: Bool
    var reportedAt: Date?
}

struct LockState: Codable, Sendable, Equatable {
    var batteryPercent: Int?
    var lastBatteryCheck: Date?
    var unlockCount: Int?
    var isOnline: Bool
    var reportedAt: Date?
}

enum DeviceReading: Codable, Sendable, Equatable {
    case fan(FanState)
    case purifier(PurifierState)
    case lock(LockState)
}

struct FanAnalytics: Codable, Sendable, Equatable {
    var energyKWh: Double?
    var runtimeHours: Double?
}

struct PurifierAnalytics: Codable, Sendable, Equatable {
    var waterSavedLiters: Double?
    var uvRuntimeHours: Double?
}

struct DeviceSnapshot: Codable, Sendable, Equatable, Identifiable {
    var info: DeviceInfo
    var reading: DeviceReading?
    var fanAnalytics: FanAnalytics?
    var purifierAnalytics: PurifierAnalytics?
    var lastUpdated: Date?

    var id: String { info.id }
}

struct GuestPin: Sendable, Equatable {
    let code: String
    let validFrom: Date
    let validUntil: Date
}

// MARK: - Commands

enum FanCommand: Sendable, Equatable {
    case power(Bool)
    /// Always absolute (1...6), never a delta. Absolute commands are idempotent, so resends are safe.
    case speed(Int)
    case sleep(Bool)
    case light(Bool)
    case brightness(Int)
    case colour(LightColour)
    /// Hours: 0 (off), 1, 2, 3 or 6.
    case timerHours(Int)

    /// JSON object body for POST /send_command. The same keys are sent to the fan over LAN (UDP 5600).
    func commandData() -> Data {
        let object: [String: Any]
        switch self {
        case .power(let on): object = ["power": on]
        case .speed(let level): object = ["speed": level]
        case .sleep(let on): object = ["sleep": on]
        case .light(let on): object = ["led": on]
        case .brightness(let percent): object = ["brightness": percent]
        case .colour(let colour): object = ["light_mode": colour.rawValue]
        case .timerHours(let hours): object = ["timer": Self.timerCode(forHours: hours)]
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// The API's timer codes: 0 off, 1 one hour, 2 two hours, 3 three hours, 4 six hours.
    static func timerCode(forHours hours: Int) -> Int {
        switch hours {
        case 1: 1
        case 2: 2
        case 3: 3
        case 6: 4
        default: 0
        }
    }

    static func hours(forTimerCode code: Int) -> Int? {
        switch code {
        case 0: 0
        case 1: 1
        case 2: 2
        case 3: 3
        case 4: 6
        default: nil
        }
    }
}

enum PurifierCommand: Sendable, Equatable {
    case mode(PurifierMode)
    case idleSleep(Bool)
    /// Epoch seconds. Only the time of day is used, and the window repeats daily.
    case sleepWindow(startUTC: UInt32, stopUTC: UInt32)
    case sleepWindowOff

    /// One key per message. The sleep window is sent as one message with sleep_mode, start_utc and stop_utc.
    func commandData() -> Data {
        let object: [String: Any]
        switch self {
        case .mode(let mode): object = ["mode": mode.rawValue]
        case .idleSleep(let on): object = ["idle_sleep": on ? 1 : 0]
        case .sleepWindow(let start, let stop): object = ["sleep_mode": 1, "start_utc": start, "stop_utc": stop]
        case .sleepWindowOff: object = ["sleep_mode": 0]
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

enum DeviceCommand: Sendable, Equatable {
    case fan(FanCommand)
    case purifier(PurifierCommand)
}

// MARK: - Command and link state (what the UI shows)

enum CommandPhase: Sendable, Equatable {
    case idle
    case pending(since: Date)
    case failed(message: String, at: Date)
}

enum LinkState: Sendable, Equatable {
    case local
    case cloud
    case offline
}

/// The verification steps of onboarding, reported by `DeviceStore.connect(…, onStage:)` as each one starts.
enum ConnectStage: Sendable {
    case credentials, devices, status
}

// MARK: - Quota

enum CallPurpose: Sendable, Equatable {
    /// Token refresh, credential checks, user commands and PIN creation. May use the reserve.
    case essential
    /// Periodic or opportunistic reads. Blocked once only the reserve is left.
    case background
}

struct QuotaStatus: Sendable, Equatable {
    let used: Int
    let limit: Int
    /// 00:00 UTC on the next day.
    let resetsAt: Date

    var remaining: Int { max(0, limit - used) }

    /// When the count resets, in the reader's own zone and relative to now: "tomorrow at 5:30 AM".
    /// The limit resets at 00:00 UTC, which is a different time of day, and often a different day, for everyone.
    func resetPhrase(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let parts = resetParts(now: now, calendar: calendar, locale: locale)
        return "\(parts.day) at \(parts.time)"
    }

    /// The same moment as two short pieces, for a caption that has little room: ("tomorrow", "5:30 AM").
    func resetParts(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> (day: String, time: String) {
        Self.parts(for: resetsAt, now: now, calendar: calendar, locale: locale)
    }

    /// The same phrase for the next 00:00 UTC, for messages that have no ledger status to hand.
    static func nextResetPhrase(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let next = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400 + 86_400)
        let parts = parts(for: next, now: now, calendar: calendar, locale: locale)
        return "\(parts.day) at \(parts.time)"
    }

    private static func parts(for moment: Date, now: Date, calendar: Calendar, locale: Locale) -> (day: String, time: String) {
        func style(_ configure: (Date.FormatStyle) -> Date.FormatStyle) -> String {
            moment.formatted(configure(Date.FormatStyle(
                date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)))
        }
        let time = moment.formatted(Date.FormatStyle(
            date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        let day: String
        if calendar.isDate(moment, inSameDayAs: now) {
            day = "today"
        } else if let next = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(moment, inSameDayAs: next) {
            day = "tomorrow"
        } else {
            day = style { $0.weekday(.wide) }
        }
        return (day, time)
    }
}

// MARK: - Errors

enum CloudError: Error, Sendable, Equatable {
    /// 401: the API key or access token is wrong, or the access token expired.
    case invalidCredentials
    /// 403: Developer Mode is off in the Atomberg Home app, or the path or method is wrong.
    case developerModeOff
    /// 429: the daily quota or the per-second limit was hit.
    case quotaExhausted
    /// Our side of the call was refused by the local quota policy (background reserve).
    case quotaReserved
    /// 400: the request is invalid. The message names the key and what the device accepts.
    case badRequest(String)
    /// 404: the device is not on the account, or has not reported state yet.
    case notFound(String)
    /// 501: the series is not supported by the API.
    case unsupported(String)
    /// 503: the device is offline, so the command was not delivered.
    case deviceOffline
    /// 504: the request took longer than 29 s. For a command, check state before retrying.
    case gatewayTimeout
    /// 500 or 502.
    case server(status: Int, message: String)
    case network(String)
    case decoding(String)
}

// MARK: - Credentials and tokens

struct Credentials: Codable, Sendable, Equatable {
    let apiKey: String
    let refreshToken: String
}

struct AccessToken: Codable, Sendable, Equatable {
    let value: String
    let expiresAt: Date
}

// MARK: - Module contracts

/// Keychain-backed store. Implemented in `Auth/`.
protocol CredentialStoring: Sendable {
    /// Whether credentials are saved, without reading them. Never raises the Keychain access prompt.
    func hasCredentials() throws -> Bool
    func loadCredentials() throws -> Credentials?
    func saveCredentials(_ credentials: Credentials) throws
    /// Removes the credentials and the cached access token.
    func deleteCredentials() throws
    func loadAccessToken() throws -> AccessToken?
    func saveAccessToken(_ token: AccessToken) throws
    /// Removes only the cached access token.
    func deleteAccessToken() throws
}

/// Daily call ledger. Implemented in `Cloud/QuotaLedger.swift`. Every HTTP attempt counts, including failed ones.
protocol QuotaAccounting: Sendable {
    func status() async -> QuotaStatus
    /// Reserves one call. Returns false only for `.background` calls that would dip into the reserve.
    /// The caller must call this before each HTTP attempt.
    func reserve(_ purpose: CallPurpose) async -> Bool
}

/// The last known catalogue, persisted so the popover is useful before the first cloud read.
struct CatalogueCache: Codable, Sendable, Equatable {
    var devices: [DeviceSnapshot]
    /// When the states were last read from the cloud.
    var savedAt: Date
    /// When the usage figures were last read. Absent in files written before they were persisted.
    var analyticsAt: Date? = nil
}

/// Disk cache. Implemented in `Persist/DiskDeviceCache.swift`.
protocol DeviceCaching: Sendable {
    func load() -> CatalogueCache?
    func save(_ cache: CatalogueCache)
}

/// Every cloud call goes through here. Implemented in `Cloud/CloudClient.swift`.
protocol CloudAPI: Sendable {
    /// Exchanges the refresh token for an access token. Stores nothing. Costs one essential call.
    func fetchAccessToken(credentials: Credentials) async throws -> AccessToken
    /// GET /get_list_of_devices. Costs one essential call.
    func listDevices() async throws -> [DeviceInfo]
    /// GET /get_device_state. Pass an empty array to read every supported device in one call.
    func readStates(deviceIDs: [String]) async throws -> [String: DeviceReading]
    /// GET /get_device_analytics for every device on the account. One call.
    func readAnalytics() async throws -> (fans: [String: FanAnalytics], purifiers: [String: PurifierAnalytics])
    /// POST /send_command. One call.
    func send(_ command: DeviceCommand, to deviceID: String) async throws
    /// POST /get_lock_dynamic_pin. The window is required for SL1 and ignored for G1.
    func guestPin(for deviceID: String, window: DateInterval?) async throws -> GuestPin
}

/// A device seen on the local network in the last `Timing.lanPresenceWindow` seconds.
struct LANPresence: Sendable, Equatable {
    let deviceID: String
    let address: String
    let lastSeen: Date
}

enum LANEvent: Sendable, Equatable {
    case presence(LANPresence)
    case state(deviceID: String, FanState)
}

enum LANSendResult: Sendable, Equatable {
    case acknowledged(FanState)
    case noAcknowledgement
    case notPresent
}

/// Local control for fans over UDP 5625 (beacons and state broadcasts) and UDP 5600 (commands).
/// Implemented in `LAN/`. Presence is per device, never per network, so a VPN or a 2.4/5 GHz switch
/// simply makes a device fall back to the cloud until its beacons return.
protocol LANControl: Sendable {
    /// Opens the listener. The first call may trigger the macOS local network prompt.
    func start() async throws
    func stop() async
    /// A stream of presence and state events. Each call returns a new stream.
    func events() -> AsyncStream<LANEvent>
    /// Non-nil only if the device was seen within `Timing.lanPresenceWindow`.
    func presence(of deviceID: String) async -> LANPresence?
    /// Sends the command, waits for a matching state broadcast, resends once, then gives up.
    func send(_ command: FanCommand, to deviceID: String) async -> LANSendResult
    /// Call when the network path changes. Clears presence so every fan falls back until beacons return.
    func forgetAllPresence() async
    /// How the listener is doing since `start()`.
    func health() async -> LANHealth
    /// A manual check: drops presence, opens a fresh socket, probes, and waits up to `Timing.lanRecheckWindow`
    /// for a fan's beacon (they come once a second). Returns what it found.
    func recheck() async -> LANHealth
}

enum LANHealth: Sendable, Equatable {
    /// A fan's beacon or state broadcast has arrived.
    case heard
    /// Listening and able to send, but no fan has been heard: the fans are on another network or segment.
    case silent
    /// The system refused the probe broadcast, which is how a missing Local Network permission shows.
    case blocked
}

// MARK: - Routing (pure, in `Store/Routing.swift`)

enum CommandRoute: Sendable, Equatable {
    case lan
    case cloud
    case unavailable(reason: String)
}
