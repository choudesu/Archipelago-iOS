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

        return makeParsed(components: components, url: url, fallbackAddress: address)
    }

    /// Build connection attempts: remote hosts prefer `wss`, local hosts prefer `ws`.
    static func connectionCandidates(_ parsed: ParsedServerURL) -> [ParsedServerURL] {
        var candidates: [ParsedServerURL] = []
        let host = parsed.websocketURL.host?.lowercased() ?? ""
        let isLocal = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")

        if isLocal {
            candidates.append(parsed)
            if let secure = upgradeToSecure(parsed) {
                candidates.append(secure)
            }
        } else {
            if let secure = upgradeToSecure(parsed) {
                candidates.append(secure)
            }
            if parsed.websocketURL.scheme == "wss" {
                candidates = [parsed]
            } else {
                candidates.append(parsed)
            }
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.websocketURL.absoluteString
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    static func upgradeToSecure(_ parsed: ParsedServerURL) -> ParsedServerURL? {
        guard var components = URLComponents(url: parsed.websocketURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard components.scheme == "ws" else { return parsed }
        components.scheme = "wss"
        guard let url = components.url else { return nil }
        return makeParsed(
            components: components,
            url: url,
            fallbackAddress: parsed.displayAddress,
            username: parsed.username,
            password: parsed.password
        )
    }

    private static func makeParsed(
        components: URLComponents,
        url: URL,
        fallbackAddress: String,
        username: String? = nil,
        password: String? = nil
    ) -> ParsedServerURL {
        ParsedServerURL(
            websocketURL: url,
            username: username ?? components.user?.removingPercentEncoding,
            password: password ?? components.password?.removingPercentEncoding,
            displayAddress: components.host.map { host in
                if let port = components.port, port != 38281 {
                    return "\(host):\(port)"
                }
                return host
            } ?? fallbackAddress
        )
    }
}
