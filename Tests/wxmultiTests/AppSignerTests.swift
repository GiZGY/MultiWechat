import Foundation
import XCTest
@testable import wxmulti

final class AppSignerTests: XCTestCase {
    func testAdHocSignatureVerifiesAndDetectsChangedResource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Probe.app")
        let contents = app.appendingPathComponent("Contents")
        let executables = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                        to: executables.appendingPathComponent("probe"))
        let plist: [String: String] = ["CFBundleIdentifier": "test.multiwechat.signing",
                                       "CFBundleExecutable": "probe", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let resource = contents.appendingPathComponent("fixture.txt")
        try Data("before".utf8).write(to: resource)
        try AppSigner().sign(appURL: app)
        let runner = ProcessRunner()
        let signature = try runner.run("/usr/bin/codesign", ["-dv", app.path])
        XCTAssertTrue(signature.stderr.contains("Signature=adhoc"))
        try Data("after".utf8).write(to: resource)
        let check = try runner.run("/usr/bin/codesign", ["--verify", "--strict", app.path], allowFailure: true)
        XCTAssertNotEqual(check.status, 0)
    }
}
