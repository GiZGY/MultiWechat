import AppKit
import Foundation

@MainActor
final class AccountAliasMenuController {
    private let store: AccountAliasStore
    private let editor = AccountAliasEditor()

    init(store: AccountAliasStore) {
        self.store = store
    }

    func actions(
        for item: StorageItem?,
        onSaved: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) -> [PanelActionModel] {
        guard let item, !item.accounts.isEmpty else {
            return []
        }
        return [
            PanelActionModel(title: "备注", style: .normal) { [weak self] in
                self?.edit(item: item, onSaved: onSaved, onError: onError)
            },
        ]
    }

    private func edit(
        item: StorageItem,
        onSaved: () -> Void,
        onError: (String) -> Void
    ) {
        let edit = editor.runModal(
            accounts: item.accounts.map(\.id),
            aliases: store.read(),
            preferredAccountID: item.latestAccountID
        )
        guard let edit else {
            return
        }
        do {
            try store.update(
                accountID: edit.accountID,
                name: edit.name,
                wechatID: edit.wechatID
            )
            onSaved()
        } catch {
            onError(error.localizedDescription)
        }
    }
}
