import Foundation

/// Every place this app may send a packet. There are two doors: the cloud client (HTTPS to one host) and the fan
/// LAN service (UDP to addresses on your own network). Both check here before they send, and
/// `scripts/check-egress.sh` fails the build if a third door appears. Nothing else in the app touches the network.
enum NetworkPolicy {
    static let cloudScheme = "https"
    static let cloudHost = "api.developer.atomberg-iot.com"
    /// 5625: fans broadcast beacons and state here. 5600: fans take commands here.
    static let lanPorts: Set<UInt16> = [5625, 5600]

    static func allowsCloud(_ url: URL) -> Bool {
        guard url.scheme == cloudScheme, url.host == cloudHost else { return false }
        // Credentials before the host ("user@") are a classic way to dress one host as another, so they are refused.
        guard url.user == nil, url.password == nil else { return false }
        return url.port == nil || url.port == 443
    }

    /// A dotted-quad IPv4 address that is private (10/8, 172.16/12, 192.168/16), link-local (169.254/16), loopback,
    /// or the limited broadcast address, on one of the two fan ports.
    static func allowsLAN(address: String, port: UInt16) -> Bool {
        guard lanPorts.contains(port) else { return false }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (255, 255): return octets[2] == 255 && octets[3] == 255
        default: return false
        }
    }
}
