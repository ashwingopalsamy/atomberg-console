import Foundation
import Testing
@testable import ATOMBERG

@Suite("Fan state broadcasts")
struct StateDecoderTests {
    /// The example from Atomberg's API documentation: R1 fan, speed 4, power on.
    private static let documented = Data(
        ("7b226465766963655f6964223a22613037363465356165653938222c226d6573736167655f6964223a2241636d42696a6d6f6d666e424a"
         + "62486341222c2273746174655f737472696e67223a2232302c312c422c352c35302e30302c302c302c52312c323830322c312c3435313432"
         + "2c302c302c302c302c302e30302c302e30302c302c302c302c454e44227d").utf8)

    @Test func parsesTheDocumentedHexMessage() throws {
        let broadcast = try #require(StateDecoder.parseBroadcast(Self.documented))
        #expect(broadcast.deviceID == "a0764e5aee98")
        #expect(broadcast.messageID == "AcmBijmomfnBJbHcA")
        let state = try #require(StateDecoder.decode(stateString: broadcast.stateString, previousSpeed: nil, series: "R1"))
        #expect(state.power)
        #expect(state.speed == 4)
        #expect(!state.light)
        #expect(!state.sleep)
        #expect(state.source == .lan)
    }

    @Test func decodesPlainJSONToo() throws {
        let json = Data(#"{"device_id":"806599345cc0","message_id":"m1","state_string":"22,1,END"}"#.utf8)
        let broadcast = try #require(StateDecoder.parseBroadcast(json))
        let state = try #require(StateDecoder.decode(stateString: broadcast.stateString, previousSpeed: nil, series: nil))
        #expect(state.power)       // 22 = 0x16: power (0x10), speed 6
        #expect(state.speed == 6)
    }

    @Test func offFanKeepsItsLastSpeed() throws {
        let state = try #require(StateDecoder.decode(stateString: "0,END", previousSpeed: 5, series: nil))
        #expect(!state.power)
        #expect(state.speed == 5)
    }

    @Test func rejectsGarbage() {
        #expect(StateDecoder.parseBroadcast(Data("ATOMBERG-CONSOLE-PROBE".utf8)) == nil)
        #expect(StateDecoder.parseBroadcast(Data([0x00, 0x01, 0x02])) == nil)
        #expect(StateDecoder.decode(stateString: "not-a-number,1", previousSpeed: nil, series: nil) == nil)
    }
}
