import Foundation
import XCTest
@testable import wxmulti

final class FileDigestTests: XCTestCase {
    func testDigestMatchesExistingShasumAcrossChunkBoundary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        for size in [0, 3, 1_048_576, 1_048_577] {
            try Data(repeating: 97, count: size).write(to: url)
            let expected = try ProcessRunner().run("/usr/bin/shasum", ["-a", "256", url.path])
                .stdout.split(separator: " ").first.map(String.init)
            XCTAssertEqual(try FileDigest.sha256(at: url), expected)
        }
    }

    func testMissingFileFailsInsteadOfReturningEmptyDigest() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try FileDigest.sha256(at: url))
    }
}
