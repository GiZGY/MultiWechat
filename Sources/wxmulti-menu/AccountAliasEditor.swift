import AppKit
import Foundation

@MainActor
struct AccountAliasEdit {
    var accountID: String
    var name: String
    var wechatID: String
}

@MainActor
final class AccountAliasEditor: NSObject {
    private var aliases: [String: AccountAlias] = [:]
    private let accountPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
    private let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    private let wechatIDField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))

    func runModal(
        accounts: [String],
        aliases: [String: AccountAlias],
        preferredAccountID: String?
    ) -> AccountAliasEdit? {
        let accountIDs = uniqueAccountIDs(accounts)
        guard !accountIDs.isEmpty else {
            return nil
        }
        self.aliases = aliases
        configurePopup(accountIDs: accountIDs, preferredAccountID: preferredAccountID)
        configureFields()

        let alert = NSAlert()
        alert.messageText = "编辑账号备注"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = accessoryView()

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn,
              let accountID = selectedAccountID else {
            return nil
        }
        return AccountAliasEdit(
            accountID: accountID,
            name: nameField.stringValue,
            wechatID: wechatIDField.stringValue
        )
    }

    private var selectedAccountID: String? {
        accountPopup.selectedItem?.representedObject as? String
    }

    private func uniqueAccountIDs(_ accounts: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for account in accounts where !seen.contains(account) {
            seen.insert(account)
            result.append(account)
        }
        return result
    }

    private func configurePopup(accountIDs: [String], preferredAccountID: String?) {
        accountPopup.removeAllItems()
        for accountID in accountIDs {
            accountPopup.addItem(withTitle: popupTitle(for: accountID))
            accountPopup.lastItem?.representedObject = accountID
        }
        if let preferredAccountID,
           let item = accountPopup.itemArray.first(where: { $0.representedObject as? String == preferredAccountID }) {
            accountPopup.select(item)
        } else {
            accountPopup.selectItem(at: 0)
        }
        accountPopup.isEnabled = accountIDs.count > 1
        accountPopup.target = self
        accountPopup.action = #selector(accountChanged)
    }

    private func configureFields() {
        nameField.placeholderString = "备注名"
        wechatIDField.placeholderString = "微信号"
        accountChanged()
    }

    private func popupTitle(for accountID: String) -> String {
        guard let label = aliases[accountID]?.label, label != accountID else {
            return accountID
        }
        return "\(label) (\(accountID))"
    }

    @objc private func accountChanged() {
        guard let accountID = selectedAccountID else {
            nameField.stringValue = ""
            wechatIDField.stringValue = ""
            return
        }
        let alias = aliases[accountID]
        nameField.stringValue = alias?.name ?? ""
        wechatIDField.stringValue = alias?.wechatID ?? ""
    }

    private func accessoryView() -> NSView {
        let accountLabel = NSTextField(labelWithString: "账号")
        let nameLabel = NSTextField(labelWithString: "备注名")
        let wechatIDLabel = NSTextField(labelWithString: "微信号")

        let grid = NSGridView(views: [
            [accountLabel, accountPopup],
            [nameLabel, nameField],
            [wechatIDLabel, wechatIDField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.yPlacement = .center
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 370, height: 100))
        wrapper.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            grid.topAnchor.constraint(equalTo: wrapper.topAnchor),
            grid.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            accountPopup.widthAnchor.constraint(equalToConstant: 300),
        ])
        return wrapper
    }
}
