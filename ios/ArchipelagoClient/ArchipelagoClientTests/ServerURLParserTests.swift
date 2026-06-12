import XCTest
@testable import ArchipelagoClient

final class ServerURLParserTests: XCTestCase {
    func testPlainHost() throws {
        let parsed = try ServerURLParser.parse("archipelago.gg:38281")
        XCTAssertEqual(parsed.displayAddress, "archipelago.gg:38281")
        XCTAssertEqual(parsed.websocketURL.scheme, "ws")
        XCTAssertEqual(parsed.websocketURL.port, 38281)
    }

    func testArchipelagoSchemeWithCredentials() throws {
        let parsed = try ServerURLParser.parse("archipelago://Player:secret@localhost:38281")
        XCTAssertEqual(parsed.username, "Player")
        XCTAssertEqual(parsed.password, "secret")
        XCTAssertEqual(parsed.websocketURL.host, "localhost")
    }

    func testWebSocketSecureScheme() throws {
        let parsed = try ServerURLParser.parse("wss://example.com")
        XCTAssertEqual(parsed.websocketURL.scheme, "wss")
        XCTAssertEqual(parsed.websocketURL.port, 38281)
    }
}
