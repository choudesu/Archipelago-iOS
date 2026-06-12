import Foundation

enum ServerURLParser {
    static func parse(_ address: String) throws -> ParsedServerURL {
        var normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            throw URLError(.badURL)
        }

        if normalized.hasPrefix("archipelago://") {
            normalized = "ws://" + normalized.dropFirst("archipelago://".count)
        } else if !normalized.contains("://") {
            normalized = "ws://\(normalized)"
        }

        guard var components = URLComponents(string: normalized) else {
            throw URLError(.badURL)
        }

        if components.scheme == "archipelago" {
            components.scheme = "ws"
        }

        if components.port == nil {
            components.port = 38281
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        return ParsedServerURL(
            websocketURL: url,
            username: components.user?.removingPercentEncoding,
            password: components.password?.removingPercentEncoding,
            displayAddress: components.host.map { host in
                if let port = components.port, port != 38281 {
                    return "\(host):\(port)"
                }
                return host
            } ?? address
        )
    }

    /// Returns a copy of the parsed URL using `wss` instead of `ws`.
    static func upgradeToSecure(_ parsed: ParsedServerURL) -> ParsedServerURL? {
        guard var components = URLComponents(url: parsed.websocketURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard components.scheme == "ws" else { return parsed }
        components.scheme = "wss"
        guard let url = components.url else { return nil }
        return ParsedServerURL(
            websocketURL: url,
            username: parsed.username,
            password: parsed.password,
            displayAddress: parsed.displayAddress
        )
    }
}
