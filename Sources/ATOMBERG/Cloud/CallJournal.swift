import Foundation

/// One line per HTTP attempt to the cloud, so "which calls did that cost?" is answered by a file instead of a guess.
/// Only the method, path and query are written: no headers, no bodies, no tokens.
/// The file is `~/Library/Application Support/ATOMBERG/calls.log`, trimmed when it passes 200 KB.
enum CallJournal {
    private static let lock = NSLock()
    private static let maxBytes = 200_000
    /// Tests point the journal at a temporary file.
    nonisolated(unsafe) static var fileURLOverride: URL?

    static func record(_ request: URLRequest, purpose: String, outcome: String) {
        var target = request.url?.path ?? "?"
        if let query = request.url?.query { target += "?\(query)" }
        let stamp = ISO8601DateFormatter().string(from: Date())
        append("\(stamp) \(request.httpMethod ?? "GET") \(target) \(purpose) \(outcome)\n")
    }

    private static func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int, size > maxBytes {
            try? FileManager.default.removeItem(at: url)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private static var fileURL: URL {
        if let fileURLOverride { return fileURLOverride }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "ATOMBERG/calls.log")
    }
}
