import Foundation
import Testing
@testable import ATOMBERG

@Suite("Device order")
struct DeviceOrderTests {
    private func info(_ id: String, kind: DeviceKind) -> DeviceInfo {
        DeviceInfo(id: id, name: id, series: "", model: nil, room: nil, kind: kind, supportedCommands: [])
    }

    private func fan(_ id: String, power: Bool) -> DeviceSnapshot {
        let state = FanState(power: power, speed: 3, sleep: false, light: false, brightness: nil, colour: nil,
                             timerHours: 0, timerElapsedMinutes: 0, isOnline: true, source: .cloud, reportedAt: nil)
        return DeviceSnapshot(info: info(id, kind: .fan), reading: .fan(state))
    }

    private func lock(_ id: String, online: Bool) -> DeviceSnapshot {
        let state = LockState(batteryPercent: 80, lastBatteryCheck: nil, unlockCount: nil, isOnline: online, reportedAt: nil)
        return DeviceSnapshot(info: info(id, kind: .lock), reading: .lock(state))
    }

    @Test func fansGoRunningThenOnButNotRunningThenOff() {
        let snapshots = [
            fan("off", power: false),
            fan("on-unreachable", power: true),
            fan("running", power: true),
            fan("also-off", power: false),
        ]
        let links: [String: LinkState] = [
            "off": .cloud, "on-unreachable": .offline, "running": .local, "also-off": .cloud,
        ]
        let group = DeviceOrder.groups(snapshots, links: links)[0]
        #expect(group.devices.map(\.id) == ["running", "on-unreachable", "off", "also-off"])
    }

    @Test func devicesOfTheSameStateKeepTheCatalogueOrder() {
        let snapshots = [fan("b", power: true), fan("a", power: true), fan("c", power: true)]
        let links: [String: LinkState] = ["a": .local, "b": .local, "c": .local]
        #expect(DeviceOrder.groups(snapshots, links: links)[0].devices.map(\.id) == ["b", "a", "c"])
    }

    @Test func eachKindGetsItsOwnGroupFansFirst() {
        let snapshots = [lock("door", online: true), fan("fan", power: true)]
        let groups = DeviceOrder.groups(snapshots, links: ["fan": .cloud, "door": .cloud])
        #expect(groups.map(\.kind) == [.fan, .lock])
    }

    @Test func anOfflineLockSinksBelowAnOnlineOne() {
        let snapshots = [lock("gone", online: false), lock("here", online: true)]
        let group = DeviceOrder.groups(snapshots, links: ["gone": .offline, "here": .cloud])[0]
        #expect(group.devices.map(\.id) == ["here", "gone"])
    }
}
