import XCTest
@testable import ArchipelagoClient

final class APCodecTests: XCTestCase {
    func testEncodeNetworkItem() throws {
        let item = NetworkItem(item: 1, location: 2, player: 3, flags: 4)
        let encoded = try APCodec.encode([["cmd": "Test", "item": item]])
        XCTAssertTrue(encoded.contains("\"class\":\"NetworkItem\""))
        XCTAssertTrue(encoded.contains("\"item\":1"))
    }

    func testDecodeNetworkItem() throws {
        let json = """
        [{"cmd":"ReceivedItems","index":0,"items":[{"class":"NetworkItem","item":10,"location":20,"player":1,"flags":0}]}]
        """
        let messages = try APCodec.decode(json)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["cmd"] as? String, "ReceivedItems")
    }

    func testDecodeVersionObject() throws {
        let json = """
        [{"cmd":"RoomInfo","version":{"class":"Version","major":0,"minor":6,"build":8}}]
        """
        let messages = try APCodec.decode(json)
        let version = messages[0]["version"]
        let parsed = APCodec.parseVersion(version as Any)
        XCTAssertEqual(parsed, APVersion(major: 0, minor: 6, build: 8))
    }

    func testRoundTripVersionInConnect() throws {
        let payload: [String: Any] = [
            "cmd": "Connect",
            "version": APVersion.clientVersion.tuple,
            "tags": ["AP", "TextOnly"]
        ]
        let encoded = try APCodec.encode([payload])
        let decoded = try APCodec.decode(encoded)
        XCTAssertEqual(decoded.first?["cmd"] as? String, "Connect")
    }
}
