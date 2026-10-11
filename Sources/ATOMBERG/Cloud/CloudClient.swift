import Foundation

actor CloudClient: CloudAPI {
    private let baseURL: URL
    private let store: any CredentialStoring
    private let quota: any QuotaAccounting
    private let session: URLSession
    private let gate = RateGate()
    private var refreshTask: Task<AccessToken, Error>?

    init(
        baseURL: URL = URL(string: "https://api.developer.atomberg-iot.com/v2")!,
        credentials: any CredentialStoring,
        quota: any QuotaAccounting,
        // Ephemeral, because the shared session caches response bodies, access token included, on disk.
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.baseURL = baseURL
        self.store = credentials
        self.quota = quota
        self.session = session
    }

    // MARK: CloudAPI

    func fetchAccessToken(credentials: Credentials) async throws -> AccessToken {
        var request = try makeRequest("get_access_token")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(credentials.refreshToken)", forHTTPHeaderField: "Authorization")
        let data = try await perform(request, purpose: .essential, retriesServerErrors: false)
        let value = try Wire.accessTokenValue(data)
        // Without a readable exp, assume 20 of the documented 24 hours. A shorter guess made every token stale after an
        // hour (the refresh margin is one hour), and each refresh is a call. The 401 retry covers a token that lives shorter.
        return AccessToken(value: value, expiresAt: JWT.expiry(of: value) ?? Date(timeIntervalSinceNow: 20 * 3_600))
    }

    func listDevices() async throws -> [DeviceInfo] {
        let data = try await authorisedCall("get_list_of_devices", purpose: .essential, retriesServerErrors: true)
        return try Wire.deviceList(data)
    }

    /// The API takes one device per call, so each id costs one call. Empty means every device.
    func readStates(deviceIDs: [String]) async throws -> [String: DeviceReading] {
        let targets = deviceIDs.isEmpty ? ["all"] : deviceIDs
        var readings: [String: DeviceReading] = [:]
        for target in targets {
            let data = try await authorisedCall(
                "get_device_state",
                query: [URLQueryItem(name: "device_id", value: target)],
                purpose: .background,
                retriesServerErrors: true
            )
            let states = try Wire.states(data, requestedID: deviceIDs.isEmpty ? nil : target)
            readings.merge(states) { _, new in new }
        }
        return readings
    }

    func readAnalytics() async throws -> (fans: [String: FanAnalytics], purifiers: [String: PurifierAnalytics]) {
        let data = try await authorisedCall(
            "get_device_analytics",
            query: [URLQueryItem(name: "device_id", value: "all")],
            purpose: .background,
            retriesServerErrors: true
        )
        return try Wire.analytics(data)
    }

    func send(_ command: DeviceCommand, to deviceID: String) async throws {
        let commandData: Data
        switch command {
        case .fan(let fan): commandData = fan.commandData()
        case .purifier(let purifier): commandData = purifier.commandData()
        }
        let body = try Wire.commandBody(deviceID: deviceID, command: commandData)
        // Any 2xx means the fan has the command. The body is never read, so an unexpected body
        // cannot turn a delivered command into a reported failure that rolls the UI back.
        _ = try await authorisedCall(
            "send_command",
            method: "POST",
            body: body,
            purpose: .essential,
            retriesServerErrors: false
        )
    }

    func guestPin(for deviceID: String, window: DateInterval?) async throws -> GuestPin {
        let body = try Wire.guestPinBody(deviceID: deviceID, window: window)
        let data = try await authorisedCall(
            "get_lock_dynamic_pin",
            method: "POST",
            body: body,
            purpose: .essential,
            retriesServerErrors: false
        )
        return try Wire.guestPin(data)
    }

    // MARK: Requests

    private func makeRequest(_ path: String, method: String = "GET", query: [URLQueryItem] = []) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw CloudError.network("invalid request URL for \(path)")
        }
        // The one door to the internet. Anything but Atomberg's API host over HTTPS is refused before it is built.
        guard NetworkPolicy.allowsCloud(url) else {
            throw CloudError.network("blocked by network policy")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        return request
    }

    /// Runs one authorised call. A 401 with a locally valid token means the server revoked or rotated
    /// it, so the token is replaced and the call is retried once. The retry is a new attempt and
    /// reserves quota like any other.
    private func authorisedCall(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        purpose: CallPurpose,
        retriesServerErrors: Bool
    ) async throws -> Data {
        let token = try await accessTokenValue()
        let first = try authorisedRequest(path, method: method, query: query, body: body, token: token)
        do {
            return try await perform(first, purpose: purpose, retriesServerErrors: retriesServerErrors)
        } catch CloudError.invalidCredentials {
            let replacement = try await accessTokenValue(rejecting: token)
            let retry = try authorisedRequest(path, method: method, query: query, body: body, token: replacement)
            return try await perform(retry, purpose: purpose, retriesServerErrors: retriesServerErrors)
        }
    }

    private func authorisedRequest(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        token: String
    ) throws -> URLRequest {
        let stored = try storedCredentials()
        var request = try makeRequest(path, method: method, query: query)
        request.setValue(stored.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func storedCredentials() throws -> Credentials {
        guard let stored = try store.loadCredentials() else {
            throw CloudError.invalidCredentials
        }
        return stored
    }

    // MARK: Access token

    /// Returns the cached token when it has at least the refresh margin left and is not the token the
    /// server just rejected. Otherwise all concurrent callers await one shared refresh. A rejected token
    /// is never reused, and a replacement another caller already saved is used rather than refreshed again.
    private func accessTokenValue(rejecting rejected: String? = nil) async throws -> String {
        // An unreadable cache is treated as absent: the cost is one refresh, not a failed call.
        if let cached = try? store.loadAccessToken(),
           cached.value != rejected,
           cached.expiresAt.timeIntervalSinceNow >= Timing.accessTokenRefreshMargin {
            return cached.value
        }
        let task: Task<AccessToken, Error>
        if let inFlight = refreshTask {
            task = inFlight
        } else {
            task = Task { try await self.refreshToken() }
            refreshTask = task
        }
        return try await task.value.value
    }

    private func refreshToken() async throws -> AccessToken {
        defer { refreshTask = nil }
        let stored = try storedCredentials()
        let token = try await fetchAccessToken(credentials: stored)
        // A failed cache write only costs one extra refresh later.
        try? store.saveAccessToken(token)
        return token
    }

    // MARK: Transport

    /// Retries only reads, only on 500 or 502, once after one second. Failed calls count against
    /// the quota, so 429 is never retried, and send and guest PIN are never retried.
    private func perform(_ request: URLRequest, purpose: CallPurpose, retriesServerErrors: Bool) async throws -> Data {
        var retriesLeft = retriesServerErrors ? 1 : 0
        while true {
            let (data, status) = try await attempt(request, purpose: purpose)
            if (200..<300).contains(status) {
                return data
            }
            if status == 500 || status == 502, retriesLeft > 0 {
                retriesLeft -= 1
                try await Task.sleep(for: .seconds(1))
                continue
            }
            throw Self.error(forStatus: status, body: data)
        }
    }

    /// Every HTTP attempt is reserved first, so a refused call sends nothing. Pacing happens after
    /// the reservation, so refused calls do not delay the next one.
    private func attempt(_ request: URLRequest, purpose: CallPurpose) async throws -> (Data, Int) {
        guard await quota.reserve(purpose) else {
            CallJournal.record(request, purpose: String(describing: purpose), outcome: "refused")
            throw CloudError.quotaReserved
        }
        await gate.wait()
        try Task.checkCancellation()
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                CallJournal.record(request, purpose: String(describing: purpose), outcome: "not-http")
                throw CloudError.network("response is not HTTP")
            }
            CallJournal.record(request, purpose: String(describing: purpose), outcome: "\(http.statusCode)")
            return (data, http.statusCode)
        } catch let error as CloudError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CancellationError {
            throw error
        } catch {
            CallJournal.record(request, purpose: String(describing: purpose), outcome: "error")
            throw CloudError.network(error.localizedDescription)
        }
    }

    /// Classifies by HTTP status, as the API specifies. The message is only payload.
    private static func error(forStatus status: Int, body: Data) -> CloudError {
        let message = Wire.errorMessage(body)
        switch status {
        case 400: return .badRequest(message)
        case 401: return .invalidCredentials
        case 403: return .developerModeOff
        case 404: return .notFound(message)
        case 429: return .quotaExhausted
        case 501: return .unsupported(message)
        case 503: return .deviceOffline
        case 504: return .gatewayTimeout
        default: return .server(status: status, message: message)
        }
    }
}
