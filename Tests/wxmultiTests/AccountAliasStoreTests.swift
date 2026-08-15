import Foundation
import XCTest
@testable import wxmulti_menu

final class AccountAliasStoreTests: XCTestCase {
    func testUpdatesAliasUsingDocumentedSchema() throws {
        let fixture = try TemporaryAliasFixture()
        defer { fixture.cleanup() }
        let store = AccountAliasStore(aliasesURL: fixture.aliasesURL)

        try store.update(accountID: "wxid_work", name: " 工作号 ", wechatID: " work_wechat_id ")

        XCTAssertEqual(
            store.read()["wxid_work"],
            AccountAlias(name: "工作号", wechatID: "work_wechat_id")
        )
        let object = try fixture.jsonObject()
        XCTAssertEqual(object["wxid_work"]?["name"], "工作号")
        XCTAssertEqual(object["wxid_work"]?["wechatID"], "work_wechat_id")
    }

    func testBlankAliasRemovesOnlyThatAccount() throws {
        let fixture = try TemporaryAliasFixture()
        defer { fixture.cleanup() }
        let store = AccountAliasStore(aliasesURL: fixture.aliasesURL)

        try store.update(accountID: "wxid_work", name: "工作号", wechatID: "work_wechat_id")
        try store.update(accountID: "wxid_life", name: "生活号", wechatID: "")
        try store.update(accountID: "wxid_work", name: " ", wechatID: "\n")

        let aliases = store.read()
        XCTAssertNil(aliases["wxid_work"])
        XCTAssertEqual(aliases["wxid_life"], AccountAlias(name: "生活号", wechatID: nil))
    }

    func testMalformedAliasFileIsNotOverwrittenByEditing() throws {
        let fixture = try TemporaryAliasFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.aliasesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{".utf8).write(to: fixture.aliasesURL)
        let store = AccountAliasStore(aliasesURL: fixture.aliasesURL)

        XCTAssertEqual(store.read(), [:])
        XCTAssertThrowsError(
            try store.update(accountID: "wxid_work", name: "工作号", wechatID: "work_wechat_id")
        )
        XCTAssertEqual(String(data: try Data(contentsOf: fixture.aliasesURL), encoding: .utf8), "{")
    }
}

private struct TemporaryAliasFixture {
    let directory: URL
    let aliasesURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wxmulti-alias-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        aliasesURL = directory.appendingPathComponent("account-aliases.json")
    }

    func jsonObject() throws -> [String: [String: String]] {
        let data = try Data(contentsOf: aliasesURL)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: [String: String]])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
