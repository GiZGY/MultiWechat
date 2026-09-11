import XCTest
@testable import wxmulti_menu

final class AccountLookupCacheTests: XCTestCase {
    func testRepeatedMenuReadsReuseLookupUntilExpiry() {
        var cache = AccountLookupCache()
        var calls = 0
        for time in 0..<30 {
            let value = cache.value(for: "container:100", now: Double(time)) {
                calls += 1
                return "account"
            }
            XCTAssertEqual(value, "account")
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cache.value(for: "container:100", now: 30) {
            calls += 1
            return "changed"
        }, "changed")
        XCTAssertEqual(calls, 2)
    }

    func testMissingAccountIsCachedAndManualRefreshBypassesIt() {
        var cache = AccountLookupCache()
        XCTAssertNil(cache.value(for: "container:100", now: 0) { nil })
        XCTAssertNil(cache.value(for: "container:100", now: 1) {
            XCTFail("A cached empty result should not start another lookup")
            return "unexpected"
        })
        XCTAssertEqual(cache.value(for: "container:100", now: 2, force: true) { "signed-in" }, "signed-in")
    }

    func testRestartedProcessAndOtherContainerAreIndependent() {
        var cache = AccountLookupCache()
        _ = cache.value(for: "first:100", now: 0) { "old" }
        XCTAssertEqual(cache.value(for: "first:101", now: 1) { "new" }, "new")
        XCTAssertEqual(cache.value(for: "second:100", now: 1) { "other" }, "other")
    }
}
