import XCTest
@testable import wxmulti

final class IdentifierTests: XCTestCase {
    func testNormalizesInstanceID() throws {
        XCTAssertEqual(try Identifier.normalizedInstanceID(" Work 01 "), "work-01")
        XCTAssertEqual(try Identifier.normalizedInstanceID("life_main"), "life-main")
    }

    func testBuildsBundleIdentifier() {
        XCTAssertEqual(
            Identifier.bundleIdentifier(base: "com.tencent.xinWeChat", instanceID: "work-01"),
            "com.tencent.xinWeChat.wxmulti.work.01"
        )
    }

    func testRejectsEmptyID() {
        XCTAssertThrowsError(try Identifier.normalizedInstanceID("   "))
    }

    func testDisplayNameDefaultsToInstanceName() {
        XCTAssertEqual(Identifier.displayName(defaultID: "life", explicitName: nil), "微信-life")
        XCTAssertEqual(Identifier.displayName(defaultID: "life", explicitName: " 微信-生活 "), "微信-生活")
    }

    func testAppBundleNameUsesDisplayName() throws {
        XCTAssertEqual(try Identifier.appBundleName(defaultID: "life", explicitName: "微信-生活"), "微信-生活.app")
        XCTAssertEqual(try Identifier.appBundleName(defaultID: "life", explicitName: "WeChatLife.app"), "WeChatLife.app")
        XCTAssertThrowsError(try Identifier.appBundleName(defaultID: "life", explicitName: "bad/name"))
    }
}
