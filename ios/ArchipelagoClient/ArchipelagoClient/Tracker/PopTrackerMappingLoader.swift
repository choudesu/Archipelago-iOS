import Foundation

enum PopTrackerMappingLoader {
    static func loadItemMapping(from rootURL: URL) -> [Int: [String]] {
        let candidates = [
            rootURL.appendingPathComponent("scripts/autotracking/item_mapping.lua")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let base = parseBaseID(named: "BASE_ITEM_ID", in: text)
                return parseMappingTable(named: "ITEM_MAPPING", in: text, baseID: base)
            }
        }
        return [:]
    }

    static func loadLocationMapping(from rootURL: URL) -> [Int: [String]] {
        let url = rootURL.appendingPathComponent("scripts/autotracking/location_mapping.lua")
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        let base = parseBaseID(named: "BASE_LOCATION_ID", in: text)
        return parseMappingTable(named: "LOCATION_MAPPING", in: text, baseID: base)
    }

    static func parseBaseID(named name: String, in text: String) -> Int {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(-?\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return 0
        }
        return Int(text[range]) ?? 0
    }

    static func parseMappingTable(named tableName: String, in text: String, baseID: Int) -> [Int: [String]] {
        guard let tableBody = extractTableBody(named: tableName, in: text) else { return [:] }
        var result: [Int: [String]] = [:]
        let entryPattern = #"\[\s*([^\]]+)\s*\]\s*=\s*\{([\s\S]*?)\}\s*,?"#
        guard let regex = try? NSRegularExpression(pattern: entryPattern) else { return [:] }
        let range = NSRange(tableBody.startIndex..., in: tableBody)
        regex.enumerateMatches(in: tableBody, range: range) { match, _, _ in
            guard let match,
                  let keyRange = Range(match.range(at: 1), in: tableBody),
                  let valueRange = Range(match.range(at: 2), in: tableBody) else { return }
            let keyText = String(tableBody[keyRange])
            let valueText = String(tableBody[valueRange])
            guard let locationID = evaluateLuaInt(keyText, baseID: baseID) else { return }
            let codes = parseCodeList(valueText)
            if !codes.isEmpty {
                result[locationID] = codes
            }
        }
        return result
    }

    private static func extractTableBody(named tableName: String, in text: String) -> String? {
        guard let markerRange = text.range(of: "\(tableName) = {") else { return nil }
        var index = markerRange.upperBound
        var depth = 1
        while index < text.endIndex {
            let char = text[index]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[markerRange.upperBound..<index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func evaluateLuaInt(_ expression: String, baseID: Int) -> Int? {
        let trimmed = expression.replacingOccurrences(of: " ", with: "")
        if let value = Int(trimmed) {
            return value
        }
        let parts = trimmed.split(separator: "+")
        var total = 0
        for part in parts {
            if part == "BASE_ITEM_ID" || part == "BASE_LOCATION_ID" {
                total += baseID
            } else if let number = Int(part) {
                total += number
            } else {
                return nil
            }
        }
        return total
    }

    private static func parseCodeList(_ text: String) -> [String] {
        let pattern = #"\{\s*"([^"]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var codes: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let codeRange = Range(match.range(at: 1), in: text) else { return }
            let code = String(text[codeRange])
            if code.hasPrefix("@") {
                codes.append(String(code.dropFirst()))
            } else {
                codes.append(code)
            }
        }
        return codes
    }
}
