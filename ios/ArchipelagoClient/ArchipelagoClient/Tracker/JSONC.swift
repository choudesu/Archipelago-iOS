import Foundation

enum JSONC {
    static func data(from text: String) throws -> Data {
        let stripped = stripComments(stripBOM(text))
        guard let data = stripped.data(using: .utf8) else {
            throw PopTrackerPackError.invalidJSON("Could not encode JSON text.")
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data(from: text))
        } catch {
            throw PopTrackerPackError.invalidJSON(error.localizedDescription)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try decode(type, from: text)
    }

    private static func stripBOM(_ text: String) -> String {
        guard text.first == "\u{FEFF}" else { return text }
        return String(text.dropFirst())
    }

    private static func stripComments(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        var inString = false
        var escaped = false

        while index < text.endIndex {
            let char = text[index]

            if inString {
                result.append(char)
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            if char == "\"" {
                inString = true
                result.append(char)
                index = text.index(after: index)
                continue
            }

            if char == "/", text.index(after: index) < text.endIndex {
                let next = text[text.index(after: index)]
                if next == "/" {
                    index = text.index(index, offsetBy: 2)
                    while index < text.endIndex, text[index] != "\n" {
                        index = text.index(after: index)
                    }
                    continue
                }
                if next == "*" {
                    index = text.index(index, offsetBy: 2)
                    while index < text.endIndex {
                        if text[index] == "*",
                           text.index(after: index) < text.endIndex,
                           text[text.index(after: index)] == "/" {
                            index = text.index(index, offsetBy: 2)
                            break
                        }
                        index = text.index(after: index)
                    }
                    continue
                }
            }

            result.append(char)
            index = text.index(after: index)
        }

        return result
    }
}
