import Foundation

enum StateDecoder {
    /// The JSON object a fan broadcasts on UDP 5625 after every change.
    struct Broadcast: Decodable, Sendable, Equatable {
        let deviceID: String
        let messageID: String
        let stateString: String

        private enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
            case messageID = "message_id"
            case stateString = "state_string"
        }
    }

    /// Accepts the raw JSON, or the same JSON written as hex text, which the vendor docs also show.
    static func parseBroadcast(_ datagram: Data) -> Broadcast? {
        let decoder = JSONDecoder()
        if let broadcast = try? decoder.decode(Broadcast.self, from: datagram) {
            return broadcast
        }
        guard let json = dataFromHexText(datagram) else { return nil }
        return try? decoder.decode(Broadcast.self, from: json)
    }

    /// `series` is accepted but not used. The bitfield already says whether a light exists, through brightness being 0.
    static func decode(stateString: String, previousSpeed: Int?, series _: String?) -> FanState? {
        let field0 = stateString.prefix(while: { $0 != "," })
        guard let bits = UInt32(field0.trimmingCharacters(in: .whitespaces)) else { return nil }

        let power = (bits & 0x10) != 0
        let light = (bits & 0x20) != 0
        let isSleeping = (bits & 0x80) != 0

        let rawSpeed = Int(bits & 0x07)
        // Speed 0 means off or unknown. The fan keeps the last speed, so fall back to it.
        let speed = rawSpeed == 0 ? (previousSpeed ?? 1) : min(rawSpeed, 6)

        // The LAN timer code is assumed to match the cloud codes.
        let timerHours = FanCommand.hours(forTimerCode: Int((bits & 0x000F_0000) >> 16)) ?? 0
        let timerElapsedMinutes = Int((bits & 0xFF00_0000) >> 24) * 4

        let rawBrightness = Int((bits & 0x0000_7F00) >> 8)
        let brightness: Int? = rawBrightness == 0 ? nil : min(max(rawBrightness, 10), 100)

        let cool = (bits & 0x08) != 0
        let warm = (bits & 0x8000) != 0
        let colour: LightColour?
        switch (cool, warm) {
        case (true, true): colour = .daylight
        case (false, true): colour = .warm
        case (true, false): colour = .cool
        case (false, false): colour = nil
        }

        return FanState(
            power: power,
            speed: speed,
            sleep: isSleeping,
            light: light,
            brightness: brightness,
            colour: colour,
            timerHours: timerHours,
            timerElapsedMinutes: timerElapsedMinutes,
            isOnline: true,
            source: .lan,
            reportedAt: Date()
        )
    }

    private static func dataFromHexText(_ text: Data) -> Data? {
        let digits = text.filter { !($0 == 0x20 || (0x09...0x0D).contains($0)) }
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            bytes.append((high << 4) | low)
        }
        return Data(bytes)
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case 0x30...0x39: return character - 0x30
        case 0x41...0x46: return character - 0x37
        case 0x61...0x66: return character - 0x57
        default: return nil
        }
    }
}
