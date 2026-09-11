import AppKit
import CoreGraphics
import Foundation

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let store = StoreReader()
    private let cli = CLI()
    private let processStatus = ProcessStatus()
    private let storageInspector = StorageInspector()
    private let storageSizeCache = StorageSizeCache()
    private let systemOpener = SystemOpener()
    private let accountAliasStore = AccountAliasStore()
    private lazy var accountAliasMenu = AccountAliasMenuController(store: accountAliasStore)
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var popoverCloseObserver: NSObjectProtocol?
    private var actionStatusResetTimer: Timer?
    private var runningSnapshot = RunningAppSnapshot.empty
    private var storageByID: [String: StorageItem] = [:]
    private var cachedStorageSizes: [String: CachedStorageSize] = [:]
    private var isRefreshingStorage = false
    private var needsStorageRefresh = false
    private var needsStorageRefreshWithSizes = false
    private var actionStatusText: String?
    private var rowStatusByInstanceID: [String: String] = [:]
    private var expandedRowID: String?

    override init() {
        super.init()
        cachedStorageSizes = storageSizeCache.read()
        item.button?.image = Self.statusIcon()
        item.button?.toolTip = "MultiWechat"
        item.button?.setAccessibilityLabel("MultiWechat")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentViewController = MultiWechatPanelViewController(model: panelModel())
        popover.contentSize = MultiWechatPanelViewController.contentSize(rows: panelRows())
        popoverCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopPopoverEventMonitoring()
            }
        }

    }

    private static func statusIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "WxMultiStatusTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let image = NSImage(systemSymbolName: "message.badge", accessibilityDescription: "MultiWechat")
        image?.isTemplate = true
        return image
    }

    @objc private func togglePopover() {
        guard let button = item.button else {
            return
        }
        if popover.isShown {
            closePopover()
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startPopoverEventMonitoring()
        updatePopover()
        refreshPanelData()
    }

    private func closePopover() {
        stopPopoverEventMonitoring()
        popover.performClose(nil)
    }

    private func startPopoverEventMonitoring() {
        stopPopoverEventMonitoring()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else {
                return event
            }
            if shouldClosePopover(for: event) {
                closePopover()
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func stopPopoverEventMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == 53 {
            return true
        }
        return false
    }

    private func refreshStatusAsync(userInitiated: Bool = false, clearingInstanceID: String? = nil, refreshStorage: Bool = true) {
        if userInitiated {
            setActionStatus("正在刷新", clearsAfter: nil)
        }
        let instances = store.read()
        let appPaths = [OfficialWeChatApp.sourcePath] + instances.map(\.appPath)
        let running = processStatus.runningSnapshot(appPaths: appPaths)
        let statusChanged = runningSnapshot != running
        runningSnapshot = running
        if let clearingInstanceID {
            rowStatusByInstanceID.removeValue(forKey: clearingInstanceID)
        }
        if refreshStorage, statusChanged, popover.isShown {
            refreshStorageAsync(includeDataSizes: false)
        }
        if userInitiated {
            setActionStatus("已刷新")
        } else if popover.isShown, statusChanged || clearingInstanceID != nil {
            updatePopover()
        }
    }

    private func refreshStorageAsync(includeDataSizes: Bool) {
        guard popover.isShown else {
            return
        }
        guard !isRefreshingStorage else {
            needsStorageRefresh = true
            needsStorageRefreshWithSizes = needsStorageRefreshWithSizes || includeDataSizes
            return
        }
        isRefreshingStorage = true
        needsStorageRefresh = false
        needsStorageRefreshWithSizes = false
        let instances = store.read()
        let runningSnapshot = self.runningSnapshot
        let inspector = self.storageInspector
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let items = inspector.scan(
                instances: instances,
                runningSnapshot: runningSnapshot,
                includeDataSizes: includeDataSizes
            )
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let mergedItems = self.storageItemsByApplyingCache(items)
                let nextStorage = Dictionary(uniqueKeysWithValues: mergedItems.map { ($0.id, $0) })
                let storageChanged = self.storageByID != nextStorage
                self.storageByID = nextStorage
                if includeDataSizes {
                    self.updateStorageSizeCache(from: nextStorage)
                }
                self.isRefreshingStorage = false
                if storageChanged, self.popover.isShown {
                    self.updatePopover()
                }
                if self.needsStorageRefresh {
                    let includeSizes = self.needsStorageRefreshWithSizes
                    self.refreshStorageAsync(includeDataSizes: includeSizes)
                    return
                }
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let hasStaleSizes = nextStorage.values.contains {
                    !$0.isDataSizeKnown || now - (self.cachedStorageSizes[$0.id]?.updatedAt ?? 0) >= 300_000
                }
                if !includeDataSizes, self.popover.isShown, hasStaleSizes {
                    self.refreshStorageAsync(includeDataSizes: true)
                }
            }
        }
    }

    private func storageItemsByApplyingCache(_ items: [StorageItem]) -> [StorageItem] {
        items.map { item in
            guard !item.isDataSizeKnown, let cached = cachedStorageSizes[item.id] else {
                return item
            }
            var next = item
            next.dataBytes = cached.dataBytes
            next.isDataSizeKnown = true
            return next
        }
    }

    private func updateStorageSizeCache(from storage: [String: StorageItem]) {
        var next = cachedStorageSizes.filter { storage[$0.key] != nil }
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        for item in storage.values where item.isDataSizeKnown {
            next[item.id] = CachedStorageSize(dataBytes: item.dataBytes, updatedAt: timestamp)
        }
        cachedStorageSizes = next
        storageSizeCache.write(next)
    }

    private func refreshPanelData(userInitiated: Bool = false) {
        refreshStatusAsync(userInitiated: userInitiated, refreshStorage: false)
        refreshStorageAsync(includeDataSizes: userInitiated)
    }

    private func updatePopover() {
        guard let controller = popover.contentViewController as? MultiWechatPanelViewController else {
            return
        }
        let rows = panelRows()
        controller.update(panelModel(rows: rows))
        let contentSize = MultiWechatPanelViewController.contentSize(rows: rows)
        if popover.contentSize != contentSize {
            popover.contentSize = contentSize
        }
    }

    private func panelModel(rows: [PanelRowModel]? = nil) -> PanelModel {
        PanelModel(
            runningSummary: runningSummary(),
            rows: rows ?? panelRows(),
            onCreate: { [weak self] in self?.createInstance() },
            onRefresh: { [weak self] in self?.refreshPanelData(userInitiated: true) },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
    }

    private func panelRows() -> [PanelRowModel] {
        let aliases = accountAliasStore.read()
        var rows: [PanelRowModel] = [officialRow(aliases: aliases)]
        rows.append(contentsOf: store.read().sorted(by: { $0.id < $1.id }).map { instanceRow(instance: $0, aliases: aliases) })
        return rows
    }

    private func officialRow(aliases: [String: AccountAlias]) -> PanelRowModel {
        let runningCount = runningSnapshot.count(for: OfficialWeChatApp.sourcePath)
        let running = runningCount > 0
        let status = running ? statusText(runningCount: runningCount) : "未运行"
        let actions = [
            PanelActionModel(title: running ? "显示" : "启动", style: .normal) { [weak self] in
                if running {
                    self?.activateApp(
                        path: OfficialWeChatApp.sourcePath,
                        bundleIdentifier: OfficialWeChatApp.bundleIdentifier,
                        actionName: "显示原版微信"
                    )
                } else {
                    self?.openOfficial()
                }
            },
        ] + accountAliasActions(for: "official") + officialStorageActions()
        return PanelRowModel(
            id: "official",
            title: "原版微信",
            detail: accountDetail(for: "official", aliases: aliases),
            usage: storageUsage(for: "official"),
            status: status,
            statusColor: running ? .systemGreen : .systemGray,
            accountIDs: accountLabels(for: "official", aliases: aliases),
            isExpanded: expandedRowID == "official",
            actions: actions,
            onToggle: { [weak self] in self?.toggleExpandedRow("official") }
        )
    }

    private func instanceRow(instance: MenuInstance, aliases: [String: AccountAlias]) -> PanelRowModel {
        let runningCount = runningSnapshot.count(for: instance.appPath)
        let running = runningCount > 0
        let pendingStatus = rowStatusByInstanceID[instance.id]
        var actions: [PanelActionModel] = [
            PanelActionModel(title: running ? "显示" : "启动", style: .normal, isEnabled: pendingStatus == nil) { [weak self] in
                if running {
                    self?.activateApp(
                        path: instance.appPath,
                        bundleIdentifier: instance.bundleIdentifier,
                        actionName: "显示\(instance.name)"
                    )
                } else {
                    self?.startInstance(id: instance.id)
                }
            },
        ]
        if running {
            actions.append(PanelActionModel(title: "关闭", style: .normal, isEnabled: pendingStatus == nil) { [weak self] in self?.stopInstance(id: instance.id) })
        }
        let reference = InstanceReference(id: instance.id, name: instance.name)
        actions.append(PanelActionModel(title: "更新", style: .normal, isEnabled: pendingStatus == nil) { [weak self] in self?.rebuildInstance(reference: reference) })
        actions.append(PanelActionModel(title: "访达", style: .normal, isEnabled: pendingStatus == nil) { [weak self] in self?.revealApp(path: instance.appPath) })
        actions.append(contentsOf: accountAliasActions(for: instance.id))
        if let storageItem = storageByID[instance.id] {
            actions.append(PanelActionModel(title: "数据", style: .normal, isEnabled: storageItem.containerExists && pendingStatus == nil) { [weak self] in
                self?.revealData(path: storageItem.containerPath)
            })
            actions.append(PanelActionModel(
                title: "清除",
                style: .destroy,
                isEnabled: storageItem.dataBytes > 0 && !running && pendingStatus == nil
            ) { [weak self] in
                self?.clearData(item: storageItem)
            })
        }
        actions.append(PanelActionModel(title: "销毁", style: .destroy, isEnabled: pendingStatus == nil) { [weak self] in self?.destroyInstance(id: instance.id) })

        return PanelRowModel(
            id: instance.id,
            title: instance.name,
            detail: accountDetail(for: instance.id, aliases: aliases),
            usage: storageUsage(for: instance.id),
            status: pendingStatus ?? (running ? statusText(runningCount: runningCount) : "未运行"),
            statusColor: pendingStatus == nil ? (running ? .systemGreen : .systemGray) : .systemOrange,
            accountIDs: accountLabels(for: instance.id, aliases: aliases),
            isExpanded: expandedRowID == instance.id,
            actions: actions,
            onToggle: { [weak self] in self?.toggleExpandedRow(instance.id) }
        )
    }

    private func toggleExpandedRow(_ id: String) {
        expandedRowID = expandedRowID == id ? nil : id
        updatePopover()
    }

    private func officialStorageActions() -> [PanelActionModel] {
        guard let storageItem = storageByID["official"] else {
            return []
        }
        return [
            PanelActionModel(title: "数据", style: .normal, isEnabled: storageItem.containerExists) { [weak self] in
                self?.revealData(path: storageItem.containerPath)
            },
        ]
    }

    private func accountAliasActions(for id: String) -> [PanelActionModel] {
        accountAliasMenu.actions(for: storageByID[id], onSaved: { [weak self] in self?.aliasEditDidSave() }, onError: { [weak self] in self?.setActionStatus($0) })
    }

    private func aliasEditDidSave() { setActionStatus("已更新账号备注"); updatePopover() }

    private func accountDetail(for id: String, aliases: [String: AccountAlias]) -> String {
        guard let item = storageByID[id] else {
            return isRefreshingStorage ? "账号扫描中" : "未发现账号"
        }
        if let latest = item.latestAccountID {
            let prefix = item.activeAccountID == latest ? "当前" : "上次"
            let label = accountLabel(for: latest, aliases: aliases)
            return item.accounts.count > 1 ? "\(prefix) \(label) · \(item.accounts.count) 个账号" : "\(prefix) \(label)"
        }
        return "未发现账号"
    }

    private func accountLabels(for id: String, aliases: [String: AccountAlias]) -> [String] {
        guard let item = storageByID[id] else {
            return []
        }
        return item.accounts.enumerated().map { index, account in
            let label = accountLabel(for: account.id, aliases: aliases)
            if account.id == item.activeAccountID {
                return "\(label)（当前）"
            }
            if item.activeAccountID == nil, index == 0 {
                return "\(label)（上次）"
            }
            return label
        }
    }

    private func accountLabel(for id: String, aliases: [String: AccountAlias]) -> String {
        aliases[id]?.label ?? id
    }

    private func storageUsage(for id: String) -> String {
        guard let item = storageByID[id] else {
            return isRefreshingStorage ? "扫描中" : "数据 --"
        }
        guard item.isDataSizeKnown else {
            return isRefreshingStorage ? "扫描中" : "数据 --"
        }
        return ByteFormatter.string(from: item.dataBytes)
    }

    private func runningSummary() -> String {
        if let actionStatusText {
            return actionStatusText
        }
        let official = runningSnapshot.count(for: OfficialWeChatApp.sourcePath) > 0 ? 1 : 0
        let namedCount = store.read().reduce(0) { $0 + runningSnapshot.count(for: $1.appPath) }
        let total = official + namedCount
        return "\(total) 个微信运行中"
    }

    private func statusText(runningCount: Int) -> String {
        runningCount > 1 ? "运行中 x\(runningCount)" : "运行中"
    }

    private func runCLI(_ args: [String], actionName: String, instanceID: String? = nil, pendingStatus: String? = nil) {
        if let instanceID, let pendingStatus {
            setRowStatus(pendingStatus, for: instanceID)
        }
        setActionStatus("正在\(actionName)", clearsAfter: nil)
        let cli = self.cli
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let succeeded = cli.run(args)
            Task { @MainActor [weak self] in
                self?.setActionStatus(succeeded ? "已\(actionName)" : "\(actionName)失败")
                self?.refreshStatusAsync(clearingInstanceID: instanceID)
            }
        }
    }

    private func setRowStatus(_ text: String, for instanceID: String) {
        rowStatusByInstanceID[instanceID] = text
        updatePopover()
    }

    private func setActionStatus(_ text: String, clearsAfter interval: TimeInterval? = 3) {
        actionStatusResetTimer?.invalidate()
        actionStatusText = text
        updatePopover()
        guard let interval else {
            return
        }
        actionStatusResetTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.actionStatusText = nil
                self?.updatePopover()
            }
        }
    }

    private func createInstance() {
        closePopover()
        let defaults = nextInstanceDefaults()
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        nameField.stringValue = defaults.name

        let alert = NSAlert()
        alert.messageText = "新建分身"
        alert.informativeText = "默认已填好名字，可直接修改。"
        alert.addButton(withTitle: "创建并启动")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = nameField
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        setActionStatus("正在创建\(name)", clearsAfter: nil)
        let id = defaults.id
        let cli = self.cli
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let succeeded = cli.run([
                "create",
                id,
                "--name",
                name,
                "--app-name",
                name,
                "--force",
                "--entitlements",
                "none",
            ]) && cli.run(["start", id])
            Task { @MainActor [weak self] in
                self?.setActionStatus(succeeded ? "已创建\(name)" : "创建\(name)失败")
                self?.refreshStatusAsync()
            }
        }
    }

    private func nextInstanceDefaults() -> (id: String, name: String) {
        let existing = Set(store.read().map(\.id))
        var index = 2
        while existing.contains("wechat-\(index)") {
            index += 1
        }
        return ("wechat-\(index)", "微信-\(index)")
    }

    private func startInstance(id: String) {
        let name = store.read().first(where: { $0.id == id })?.name ?? id
        runCLI(["start", id], actionName: "启动\(name)", instanceID: id, pendingStatus: "启动中")
    }

    private func stopInstance(id: String) {
        let name = store.read().first(where: { $0.id == id })?.name ?? id
        runCLI(["stop", id], actionName: "关闭\(name)", instanceID: id, pendingStatus: "关闭中")
    }

    private func rebuildInstance(reference: InstanceReference) {
        let id = reference.id
        let name = reference.name
        let cli = self.cli
        setRowStatus("更新中", for: id)
        setActionStatus("正在更新\(name)", clearsAfter: nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let succeeded = cli.run(["stop", id])
                && cli.run(["rebuild", id])
                && cli.run(["start", id])
            Task { @MainActor [weak self] in
                self?.setActionStatus(succeeded ? "已更新\(name)" : "更新\(name)失败")
                self?.refreshStatusAsync(clearingInstanceID: id)
            }
        }
    }

    private func destroyInstance(id: String) {
        let cli = self.cli
        let name = store.read().first(where: { $0.id == id })?.name ?? id
        setRowStatus("销毁中", for: id)
        setActionStatus("正在销毁\(name)", clearsAfter: nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let succeeded = cli.run(["stop", id]) && cli.run(["remove", id, "--delete-app"])
            Task { @MainActor [weak self] in
                if self?.expandedRowID == id {
                    self?.expandedRowID = nil
                }
                self?.setActionStatus(succeeded ? "已销毁\(name)" : "销毁\(name)失败")
                self?.refreshStatusAsync(clearingInstanceID: id)
            }
        }
    }

    private func activateApp(path: String, bundleIdentifier: String, actionName: String) {
        guard let pid = runningSnapshot.pids(for: path).sorted().last else {
            setActionStatus("\(actionName)失败")
            return
        }
        closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.activateAppWindow(
                pid: pid,
                path: path,
                bundleIdentifier: bundleIdentifier,
                actionName: actionName
            )
        }
    }

    private func activateAppWindow(pid: Int32, path: String, bundleIdentifier: String, actionName: String) {
        let app = NSRunningApplication(processIdentifier: pid)
        _ = app?.unhide()
        _ = systemOpener.activateApplication(bundleIdentifier: bundleIdentifier)
        _ = app?.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else {
                return
            }
            if !self.hasVisibleWindow(pid: pid) {
                _ = self.systemOpener.activateApplication(bundleIdentifier: bundleIdentifier)
                _ = self.systemOpener.activateApplication(at: path)
                _ = app?.activate(options: [.activateAllWindows])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else {
                    return
                }
                self.setActionStatus(self.hasVisibleWindow(pid: pid) ? "已\(actionName)" : "\(actionName)失败")
            }
        }
    }

    private func hasVisibleWindow(pid: Int32) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            let ownerPID = (window[kCGWindowOwnerPID as String] as? Int).map(Int32.init)
            guard ownerPID == pid else {
                return false
            }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            guard layer == 0, alpha > 0 else {
                return false
            }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else {
                return false
            }
            return width >= 120 && height >= 120
        }
    }

    private func revealApp(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            setActionStatus("访达打开失败")
            return
        }
        if systemOpener.reveal(path) {
            setActionStatus("已打开访达")
        } else {
            setActionStatus("访达打开失败")
        }
    }

    private func revealData(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            setActionStatus("数据目录不存在")
            return
        }
        if systemOpener.reveal(path) || systemOpener.openParent(of: path) {
            setActionStatus("已显示数据目录")
        } else {
            setActionStatus("数据目录打开失败")
        }
    }

    private func clearData(item: StorageItem) {
        setRowStatus("清除中", for: item.id)
        setActionStatus("正在清除\(item.title)数据", clearsAfter: nil)
        let inspector = self.storageInspector
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try inspector.clearContainer(for: item)
                Task { @MainActor [weak self] in
                    self?.setActionStatus("已清除\(item.title)数据")
                    self?.refreshStorageAsync(includeDataSizes: true)
                    self?.refreshStatusAsync(clearingInstanceID: item.id)
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.setActionStatus(error.localizedDescription)
                    self?.rowStatusByInstanceID.removeValue(forKey: item.id)
                    self?.updatePopover()
                }
            }
        }
    }

    private func openOfficial() {
        if systemOpener.open(OfficialWeChatApp.sourcePath) {
            setActionStatus("已启动原版微信")
        } else {
            setActionStatus("启动原版微信失败")
        }
    }

}

@main
@MainActor
struct WxMultiMenuApp {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }
}
