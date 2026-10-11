import Foundation
import Testing
@testable import ATOMBERG

@Suite("Network policy")
struct NetworkPolicyTests {
    @Test func allowsOnlyTheAtombergApiOverHTTPS() {
        #expect(NetworkPolicy.allowsCloud(URL(string: "https://api.developer.atomberg-iot.com/v2/get_device_state")!))
        #expect(NetworkPolicy.allowsCloud(URL(string: "https://api.developer.atomberg-iot.com:443/v2/x")!))
    }

    @Test(arguments: [
        "http://api.developer.atomberg-iot.com/v2/x",
        "https://example.com/v2/x",
        "https://api.developer.atomberg-iot.com.evil.test/v2/x",
        "https://api.developer.atomberg-iot.com@evil.test/v2/x",
        "https://user:pw@api.developer.atomberg-iot.com/v2/x",
        "https://api.developer.atomberg-iot.com:8443/v2/x",
        "ftp://api.developer.atomberg-iot.com/x",
    ])
    func refusesEverythingElse(_ string: String) {
        #expect(!NetworkPolicy.allowsCloud(URL(string: string)!))
    }

    @Test(arguments: ["10.0.0.5", "172.16.0.1", "172.31.255.1", "192.168.1.37", "169.254.1.1", "127.0.0.1", "255.255.255.255"])
    func allowsLocalAddressesOnFanPorts(_ address: String) {
        #expect(NetworkPolicy.allowsLAN(address: address, port: 5600))
        #expect(NetworkPolicy.allowsLAN(address: address, port: 5625))
    }

    @Test(arguments: ["8.8.8.8", "172.15.0.1", "172.32.0.1", "255.255.255.0", "192.169.1.1", "example.com", "", "1.2.3", "300.1.1.1"])
    func refusesPublicAndMalformedAddresses(_ address: String) {
        #expect(!NetworkPolicy.allowsLAN(address: address, port: 5600))
    }

    @Test func refusesOtherPorts() {
        #expect(!NetworkPolicy.allowsLAN(address: "192.168.1.37", port: 80))
        #expect(!NetworkPolicy.allowsLAN(address: "192.168.1.37", port: 5000))
    }

    @Test func hasNoThirdPartyPackages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
        #expect(!manifest.contains(".package("))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Package.resolved").path))
    }
}
