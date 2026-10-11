import Foundation

/// Conversion between the cloud API's JSON and domain types. Wire shapes never leave this file.
enum Wire {
    // MARK: Responses

    static func deviceList(_ data: Data) throws -> [DeviceInfo] {
        try payload(DevicesMessage.self, data).devicesList.elements.compactMap { $0.info }
    }

    /// Absent non-optional fields take the value the domain uses for "none" (speed 1, timer 0,
    /// flags false). The domain structs cannot express "unknown" for those, so this is the one
    /// place where a missing key is not nil.
    static func states(_ data: Data, requestedID: String?) throws -> [String: DeviceReading] {
        var readings: [String: DeviceReading] = [:]
        for item in try payload(StatesMessage.self, data).deviceState.elements {
            guard let id = item.deviceId ?? requestedID, let reading = deviceReading(from: item) else { continue }
            readings[id] = reading
        }
        return readings
    }

    static func analytics(_ data: Data) throws -> (fans: [String: FanAnalytics], purifiers: [String: PurifierAnalytics]) {
        var fans: [String: FanAnalytics] = [:]
        var purifiers: [String: PurifierAnalytics] = [:]
        for item in try payload(AnalyticsMessage.self, data).deviceState.elements {
            guard let id = item.deviceId else { continue }
            if item.powerConsumption != nil || item.runtime != nil {
                fans[id] = FanAnalytics(energyKWh: item.powerConsumption, runtimeHours: item.runtime)
            } else if item.waterSavedLiters != nil || item.uvRuntimeHours != nil {
                purifiers[id] = PurifierAnalytics(
                    waterSavedLiters: item.waterSavedLiters,
                    uvRuntimeHours: item.uvRuntimeHours
                )
            }
        }
        return (fans: fans, purifiers: purifiers)
    }

    static func guestPin(_ data: Data) throws -> GuestPin {
        let pin = try payload(PinMessage.self, data).data
        return GuestPin(
            code: pin.otp,
            validFrom: Date(timeIntervalSince1970: pin.validStartTime),
            validUntil: Date(timeIntervalSince1970: pin.validEndTime)
        )
    }

    static func accessTokenValue(_ data: Data) throws -> String {
        try payload(TokenMessage.self, data).accessToken
    }

    private struct ErrorBody: Decodable {
        let message: String?
    }

    static func errorMessage(_ data: Data) -> String {
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let message = body.message {
            return message
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Request bodies

    /// Embeds the object from `commandData()` rather than re-encoding the domain value, so the
    /// cloud and LAN paths send the same keys.
    static func commandBody(deviceID: String, command: Data) throws -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: command) else {
            throw CloudError.badRequest("command is not valid JSON")
        }
        return try JSONSerialization.data(withJSONObject: ["device_id": deviceID, "command": object])
    }

    static func guestPinBody(deviceID: String, window: DateInterval?) throws -> Data {
        var body: [String: Any] = ["device_id": deviceID]
        if let window {
            body["start_time"] = Int(window.start.timeIntervalSince1970.rounded())
            body["end_time"] = Int(window.end.timeIntervalSince1970.rounded())
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: Mapping

    private static func deviceReading(from item: StateDTO) -> DeviceReading? {
        if item.power != nil || item.lastRecordedSpeed != nil {
            return .fan(fanState(item))
        }
        if item.mode != nil || item.chokingFaults != nil || item.inputTds != nil {
            return .purifier(purifierState(item))
        }
        if item.battery != nil || item.nUnlocks != nil {
            return .lock(lockState(item))
        }
        return nil
    }

    private static func fanState(_ item: StateDTO) -> FanState {
        FanState(
            power: item.power?.value ?? false,
            speed: item.lastRecordedSpeed ?? 1,
            sleep: item.sleepMode?.value ?? false,
            light: item.led?.value ?? false,
            brightness: item.lastRecordedBrightness,
            colour: item.lastRecordedColor.flatMap { LightColour(rawValue: $0) },
            timerHours: item.timerHours ?? 0,
            timerElapsedMinutes: item.timerTimeElapsedMins ?? 0,
            isOnline: item.isOnline?.value ?? false,
            source: .cloud,
            reportedAt: epochDate(item.tsEpochSeconds)
        )
    }

    private static func purifierState(_ item: StateDTO) -> PurifierState {
        PurifierState(
            mode: item.mode.flatMap { PurifierMode(rawValue: $0) },
            inputTDS: item.inputTds,
            storedTDS: item.tankTds,
            idleSleep: item.idleSleep?.value ?? false,
            sleepWindowOn: item.sleepMode?.value ?? false,
            sleepStartUTC: item.startUtc.flatMap { UInt32(exactly: $0) },
            sleepStopUTC: item.stopUtc.flatMap { UInt32(exactly: $0) },
            faultDescriptions: (item.chokingFaults?.descriptions ?? []) + (item.systemFaults?.descriptions ?? []),
            filterChoked: item.chokingFaults?.filterChoke?.value ?? false,
            isOnline: item.isOnline?.value ?? false,
            reportedAt: epochDate(item.tsEpochSeconds)
        )
    }

    private static func lockState(_ item: StateDTO) -> LockState {
        LockState(
            batteryPercent: item.battery,
            lastBatteryCheck: epochDate(item.lastBatteryTime),
            unlockCount: item.nUnlocks,
            isOnline: item.isOnline?.value ?? false,
            reportedAt: epochDate(item.tsEpochSeconds)
        )
    }

    private static func epochDate(_ seconds: Double?) -> Date? {
        seconds.map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: Envelope

    /// Reads only the message. The HTTP status has already classified the response, so the envelope's
    /// status string is not checked a second time.
    private static func payload<Message: Decodable>(_ type: Message.Type, _ data: Data) throws -> Message {
        try decode(Envelope<Message>.self, from: data).message
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw CloudError.decoding(String(describing: error))
        }
    }
}

// MARK: - Wire shapes

fileprivate struct Envelope<Message: Decodable>: Decodable {
    let message: Message
}

/// Decodes any JSON value without reading it.
fileprivate struct Ignored: Decodable {
    init(from decoder: Decoder) throws {}
}

/// Decodes each element on its own, so one malformed item drops only itself. A non-empty array in
/// which no element decodes is a decoding failure, not an empty result.
fileprivate struct Lossy<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        var skipped = 0
        while !container.isAtEnd {
            do {
                decoded.append(try container.decode(Element.self))
            } catch {
                // A failed decode does not advance the container, so the bad element is consumed here.
                _ = try container.decode(Ignored.self)
                skipped += 1
            }
        }
        if decoded.isEmpty, skipped > 0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "none of \(skipped) array elements decoded"
            ))
        }
        elements = decoded
    }
}

/// The API uses both JSON booleans and 0/1 integers for flags.
fileprivate struct Flag: Decodable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            value = flag
        } else {
            value = try container.decode(Int.self) != 0
        }
    }
}

fileprivate struct DeviceDTO: Decodable {
    let deviceId: String?
    let name: String?
    let series: String?
    let model: String?
    let room: String?
    let deviceType: String?
    let supportedCommands: [CommandDTO]?
    let metadata: MetadataDTO?

    /// Unknown device types and devices without an id are skipped.
    var info: DeviceInfo? {
        guard let id = deviceId, let kind = deviceType.flatMap({ DeviceKind(rawValue: $0) }) else {
            return nil
        }
        return DeviceInfo(
            id: id,
            name: name ?? id,
            series: series ?? "",
            model: model,
            room: room,
            kind: kind,
            supportedCommands: (supportedCommands ?? []).compactMap { $0.domain },
            ssid: metadata?.ssid
        )
    }
}

/// Registration details that vary by device. Whatever shape arrives, it never fails the device that carries it.
fileprivate struct MetadataDTO: Decodable {
    let ssid: String?

    private enum CodingKeys: String, CodingKey { case ssid }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        ssid = (try? container?.decode(String.self, forKey: .ssid)).flatMap { $0.isEmpty ? nil : $0 }
    }
}

fileprivate struct CommandDTO: Decodable {
    let command: String?
    let accepts: String?
    let requires: [String]?
    let subKeyOf: String?

    var domain: SupportedCommand? {
        guard let command else { return nil }
        return SupportedCommand(
            command: command,
            accepts: accepts ?? "",
            requires: requires ?? [],
            subKeyOf: subKeyOf
        )
    }
}

/// One object covers all three kinds. Each kind is recognised by the keys it carries.
fileprivate struct StateDTO: Decodable {
    let deviceId: String?
    let power: Flag?
    let lastRecordedSpeed: Int?
    let sleepMode: Flag?
    let led: Flag?
    let isOnline: Flag?
    let timerHours: Int?
    let timerTimeElapsedMins: Int?
    let tsEpochSeconds: Double?
    let lastRecordedBrightness: Int?
    let lastRecordedColor: String?
    let mode: Int?
    let inputTds: Double?
    let tankTds: Double?
    let idleSleep: Flag?
    let startUtc: Int?
    let stopUtc: Int?
    let chokingFaults: FaultsDTO?
    let systemFaults: FaultsDTO?
    let battery: Int?
    let lastBatteryTime: Double?
    let nUnlocks: Int?
}

fileprivate struct FaultsDTO: Decodable {
    let descriptions: [String]?
    let filterChoke: Flag?
}

fileprivate struct AnalyticsDTO: Decodable {
    let deviceId: String?
    let powerConsumption: Double?
    let runtime: Double?
    let waterSavedLiters: Double?
    let uvRuntimeHours: Double?
}

// The snake_case decoding strategy maps the keys below. CodingKeys with snake_case raw values would
// never match, because the decoder converts the incoming keys before looking them up.
fileprivate struct DevicesMessage: Decodable {
    let devicesList: Lossy<DeviceDTO>
}

fileprivate struct StatesMessage: Decodable {
    let deviceState: Lossy<StateDTO>
}

fileprivate struct AnalyticsMessage: Decodable {
    let deviceState: Lossy<AnalyticsDTO>
}

fileprivate struct PinMessage: Decodable {
    let data: PinDTO
}

fileprivate struct PinDTO: Decodable {
    let otp: String
    let validStartTime: Double
    let validEndTime: Double
}

fileprivate struct TokenMessage: Decodable {
    let accessToken: String
}
