import Foundation
import Testing
@testable import ATOMBERG

@Suite("Token expiry and call journal")
struct JWTAndJournalTests {
    private func token(payload: String) -> String {
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "e30.\(encoded).signature"
    }

    @Test func readsTheExpiryClaim() {
        let date = JWT.expiry(of: token(payload: #"{"exp":1760000000}"#))
        #expect(date == Date(timeIntervalSince1970: 1_760_000_000))
    }

    @Test func returnsNilWhenThereIsNoClaim() {
        #expect(JWT.expiry(of: token(payload: #"{"sub":"x"}"#)) == nil)
        #expect(JWT.expiry(of: "not a token") == nil)
    }

    @Test func theJournalNeverWritesSecrets() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "calls-\(UUID().uuidString).log")
        CallJournal.fileURLOverride = file
        defer { CallJournal.fileURLOverride = nil; try? FileManager.default.removeItem(at: file) }

        var request = URLRequest(url: URL(string: "https://api.developer.atomberg-iot.com/v2/send_command")!)
        request.httpMethod = "POST"
        request.setValue("SECRET-API-KEY", forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer SECRET-TOKEN", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"device_id":"SECRET-BODY"}"#.utf8)
        CallJournal.record(request, purpose: "essential", outcome: "200")

        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("POST /v2/send_command essential 200"))
        #expect(!text.contains("SECRET"))
    }
}
