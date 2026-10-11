import Foundation
import Testing
@testable import ATOMBERG

/// `docs/faq.json` feeds the website, its FAQ markup and the MCP tools. The in-app FAQ must say the same thing.
@Suite("FAQ sync")
struct FaqSyncTests {
    private struct Entry: Decodable {
        let q: String
        let a: String
        let app: Bool
    }

    @Test func theInAppFaqMatchesTheSharedSource() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/faq.json")
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        let expected = entries.filter(\.app).map { [$0.q, $0.a] }
        let actual = FaqDetail.entries.map { [$0.question, $0.answer] }
        #expect(actual == expected)
    }
}
