import Foundation

enum Routing {
    static func route(for command: DeviceCommand, kind: DeviceKind, lanPresent: Bool, quota: QuotaStatus?) -> CommandRoute {
        if case .fan = command, kind == .fan, lanPresent {
            return .lan
        }
        guard cloudAllowed(quota) else {
            return .unavailable(reason: "No cloud calls left today. They reset at 00:00 UTC.")
        }
        return .cloud
    }

    /// A nil quota means the ledger has not reported yet, so cloud is allowed.
    static func cloudAllowed(_ quota: QuotaStatus?) -> Bool {
        quota.map { $0.remaining > 0 } ?? true
    }
}

enum OptimisticReducer {
    static func apply(_ command: DeviceCommand, to reading: DeviceReading) -> DeviceReading? {
        switch (command, reading) {
        case (.fan(let fan), .fan(var state)):
            applyFan(fan, to: &state)
            return .fan(state)
        case (.purifier(let purifier), .purifier(var state)):
            applyPurifier(purifier, to: &state)
            return .purifier(state)
        default:
            return nil
        }
    }

    private static func applyFan(_ command: FanCommand, to state: inout FanState) {
        switch command {
        case .power(let on):
            state.power = on
        case .speed(let level):
            state.speed = level
            state.power = true
        case .sleep(let on):
            state.sleep = on
        case .light(let on):
            state.light = on
        case .brightness(let percent):
            state.brightness = percent
        case .colour(let colour):
            state.colour = colour
        case .timerHours(let hours):
            state.timerHours = hours
        }
    }

    private static func applyPurifier(_ command: PurifierCommand, to state: inout PurifierState) {
        switch command {
        case .mode(let mode):
            state.mode = mode
        case .idleSleep(let on):
            state.idleSleep = on
        case .sleepWindow(let start, let stop):
            state.sleepWindowOn = true
            state.sleepStartUTC = start
            state.sleepStopUTC = stop
        case .sleepWindowOff:
            state.sleepWindowOn = false
        }
    }
}
