import Foundation
import Testing
@testable import ATOMBERG

@Suite("Cloud wire format")
struct WireTests {
    @Test func readsAFanState() throws {
        let json = Data("""
        {"status":"Success","message":{"device_state":[
          {"device_id":"806599345cc0","power":true,"last_recorded_speed":3,"sleep_mode":false,"led":false,
           "is_online":true,"timer_hours":0,"timer_time_elapsed_mins":0,"ts_epoch_seconds":1760000000}]}}
        """.utf8)
        let readings = try Wire.states(json, requestedID: nil)
        guard case .fan(let state)? = readings["806599345cc0"] else {
            Issue.record("expected a fan reading")
            return
        }
        #expect(state.power)
        #expect(state.speed == 3)
        #expect(state.isOnline)
        #expect(state.source == .cloud)
    }

    @Test func acceptsFlagsAsBooleansOrIntegers() throws {
        let json = Data(#"{"message":{"device_state":[{"device_id":"a","power":1,"last_recorded_speed":2,"is_online":0}]}}"#.utf8)
        guard case .fan(let state)? = try Wire.states(json, requestedID: nil)["a"] else {
            Issue.record("expected a fan reading")
            return
        }
        #expect(state.power)
        #expect(!state.isOnline)
    }

    @Test func readsTheDeviceListAndItsNetwork() throws {
        let json = Data("""
        {"status":"Success","message":{"devices_list":[
          {"device_id":"806599345cc0","name":"Fan","series":"R1","model":"renesa","room":"Renesa Smart",
           "device_type":"fan","metadata":{"ssid":"Home"},
           "supported_commands":[{"command":"power","accepts":"true or false","requires":[]}]},
          {"device_id":"8cfd49565010","name":"Living Room","series":"R3","model":"renesa_halo",
           "device_type":"fan","metadata":"unexpected"}]}}
        """.utf8)
        let devices = try Wire.deviceList(json)
        #expect(devices.count == 2)
        #expect(devices[0].ssid == "Home")
        #expect(devices[0].kind == .fan)
        #expect(devices[1].ssid == nil)       // a malformed metadata value never drops the device
    }

    @Test func buildsOneCommandBodyForBothPaths() throws {
        let body = try Wire.commandBody(deviceID: "806599345cc0", command: FanCommand.speed(4).commandData())
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["device_id"] as? String == "806599345cc0")
        #expect((object["command"] as? [String: Any])?["speed"] as? Int == 4)
    }
}
