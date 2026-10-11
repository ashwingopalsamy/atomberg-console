import Foundation

enum JWT {
    /// Reads the `exp` claim without verifying the signature. The token is only used as a cache
    /// expiry hint; the server remains the authority.
    static func expiry(of token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONDecoder().decode(Claims.self, from: data),
              let exp = claims.exp else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private struct Claims: Decodable {
        let exp: Double?
    }
}
