import Foundation
import XCTest
@testable import wxmulti

final class HelperExecutableRecoveryTests: XCTestCase {
    func testReplacesLegacyScriptWithBinaryAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("helper")
        try Data("#!/bin/zsh\nexec missing-file\n".utf8).write(to: target)
        let source = URL(fileURLWithPath: "/usr/bin/true")
        XCTAssertTrue(try HelperExecutableRecovery.restoreIfNeeded(at: target, candidates: [target, source]))
        XCTAssertEqual(try Data(contentsOf: target), try Data(contentsOf: source))
        XCTAssertFalse(try HelperExecutableRecovery.restoreIfNeeded(at: target, candidates: []))
    }

    func testInvalidRecoverySourceLeavesExistingFileUntouched() throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: target) }
        let script = Data("#!/bin/zsh\n".utf8)
        try script.write(to: target)
        XCTAssertThrowsError(try HelperExecutableRecovery.restoreIfNeeded(at: target, candidates: [target]))
        XCTAssertEqual(try Data(contentsOf: target), script)
    }
}
