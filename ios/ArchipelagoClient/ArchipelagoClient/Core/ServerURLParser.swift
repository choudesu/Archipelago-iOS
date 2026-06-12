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
}
