import Foundation

/// How the home list is arranged. Devices sit in one card per kind (fans, purifiers, locks). Inside a card the ones
/// doing something come first: on and running, then on but not running, then off. Nothing is labelled; the order
/// alone keeps the list useful. Devices that tie keep the order the catalogue gave them.
enum DeviceOrder {
    struct Group: Identifiable, Equatable {
        let kind: DeviceKind
        let devices: [DeviceSnapshot]
        var id: DeviceKind { kind }
    }

    /// 0: on and running. 1: on but not running, or not known yet. 2: off, or unreachable.
    /// A purifier or a lock has no power switch, so reachable counts as on.
    static func activity(of snapshot: DeviceSnapshot, link: LinkState?) -> Int {
        switch snapshot.reading {
        case .fan(let state)?:
            guard state.power else { return 2 }
            return link != nil && link != .offline ? 0 : 1
        case .purifier(let state)?:
            return state.isOnline && link != .offline ? 0 : 2
        case .lock(let state)?:
            return state.isOnline && link != .offline ? 0 : 2
        case nil:
            return 1
        }
    }

    static func groups(_ snapshots: [DeviceSnapshot], links: [String: LinkState]) -> [Group] {
        DeviceKind.allCases.compactMap { kind in
            let members = snapshots.filter { $0.info.kind == kind }
            guard !members.isEmpty else { return nil }
            let ordered = members.enumerated()
                .map { (offset: $0.offset, device: $0.element, rank: activity(of: $0.element, link: links[$0.element.id])) }
                .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.offset < $1.offset }
                .map(\.device)
            return Group(kind: kind, devices: ordered)
        }
    }
}
