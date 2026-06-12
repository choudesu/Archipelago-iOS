import XCTest
@testable import ArchipelagoClient

final class DataPackageChecksumTests: XCTestCase {
    func testArchipelagoPackageChecksumIsStable() {
        let package = GamesPackage(
            itemNameToID: ["Nothing": -1],
            locationNameToID: ["Cheat Console": -1, "Server": -2],
            itemNameGroups: nil,
            locationNameGroups: nil,
            checksum: nil
        )
        let checksum = DataPackageChecksum.checksum(for: package)
        XCTAssertFalse(checksum.isEmpty)
        XCTAssertEqual(checksum.count, 40)
    }
}
