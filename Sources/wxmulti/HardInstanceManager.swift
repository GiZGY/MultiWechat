import Foundation

struct HardInstanceManager {
    private let paths: WxMultiPaths
    private let repository: HardInstanceStoreRepository
    private let patcher: WeChatBinaryPatcher
    private let inspector: ProcessInspector
    private let runner: ProcessRunner
    private let locator: WeChatLocator

    init(
        paths: WxMultiPaths = .defaults(),
        runner: ProcessRunner = ProcessRunner(),
        locator: WeChatLocator = WeChatLocator()
    ) {
        self.paths = paths
        self.repository = HardInstanceStoreRepository(storeURL: paths.hardStoreURL)
        self.runner = runner
        self.locator = locator
        self.patcher = WeChatBinaryPatcher(locator: locator, runner: runner)
        self.inspector = ProcessInspector(runner: runner)
    }

    func list() throws {
        try paths.ensureBaseDirectories()
        let store = try repository.load()
        if store.instances.isEmpty {
            print("暂无硬多开槽位")
            return
        }
        for instance in store.instances.sorted(by: { $0.id < $1.id }) {
            let runningCount = try runningMainProcesses(for: instance).count
            let status = runningCount > 0 ? "运行中 x\(runningCount)" : "未运行"
            print("\(instance.id)\t\(instance.name)\t\(status)\t\(instance.appPath)")
        }
    }

    func create(id rawID: String, name rawName: String?, sourcePath: String?, targetPath: String?, force: Bool) throws {
        try paths.ensureBaseDirectories()
        let id = try Identifier.normalizedInstanceID(rawID)
        let source = try locator.resolve(sourcePath: sourcePath)
        let name = Identifier.displayName(defaultID: id, explicitName: rawName)
        let appPath = try resolvedAppPath(id: id, name: name, explicitPath: targetPath)
        var store = try repository.load()

        if let existingIndex = store.instances.firstIndex(where: { $0.id == id }) {
            if !force {
                try fail("硬多开槽位已存在: \(id)。需要重建时请加 --force")
            }
            let existing = store.instances[existingIndex]
            if try !runningProcesses(for: existing).isEmpty {
                try fail("硬多开槽位正在运行，请先 hard-stop \(id) 后再重建")
            }
            store.instances.remove(at: existingIndex)
        }

        try patcher.installPatchedClone(
            sourcePath: source.appURL.path,
            targetPath: appPath,
            force: force,
            displayName: name
        )

        let now = Int64(Date().timeIntervalSince1970)
        let profile = HardInstanceProfile(
            id: id,
            name: name,
            appPath: appPath,
            sourceAppPath: source.appURL.path,
            sourceShortVersion: source.shortVersion,
            sourceBundleVersion: source.bundleVersion,
            createdAt: now,
            updatedAt: now,
            lastLaunchedAt: nil
        )
        store.instances.append(profile)
        store.instances.sort { $0.id < $1.id }
        try repository.save(store)
        print("硬多开槽位已创建: \(id) -> \(appPath)")
    }

    func start(id rawID: String, count: Int) throws {
        guard count > 0 else {
            try fail("启动数量必须大于 0")
        }
        var store = try repository.load()
        let id = try Identifier.normalizedInstanceID(rawID)
        let index = try indexOfInstance(id: id, in: store)
        let instance = store.instances[index]
        guard FileManager.default.fileExists(atPath: instance.appPath) else {
            try fail("硬多开 App 不存在，请先重建槽位: \(instance.appPath)")
        }
        try patcher.launch(sourcePath: instance.appPath, count: count)
        store.instances[index].lastLaunchedAt = Int64(Date().timeIntervalSince1970)
        try repository.save(store)
    }

    func stop(id rawID: String, mode: PatchedStopMode) throws {
        let store = try repository.load()
        let id = try Identifier.normalizedInstanceID(rawID)
        let instance = try instance(id: id, in: store)
        try patcher.stopPatched(targetPath: instance.appPath, mode: mode)
    }

    func rename(id rawID: String, name rawName: String) throws {
        var store = try repository.load()
        let id = try Identifier.normalizedInstanceID(rawID)
        let index = try indexOfInstance(id: id, in: store)
        let name = Identifier.displayName(defaultID: id, explicitName: rawName)
        let instance = store.instances[index]
        let running = try !runningProcesses(for: instance).isEmpty

        let infoURL = URL(fileURLWithPath: instance.appPath)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        if !running, FileManager.default.fileExists(atPath: infoURL.path) {
            var plist = try PlistEditor.readDictionary(infoURL)
            plist["CFBundleName"] = name
            plist["CFBundleDisplayName"] = name
            try PlistEditor.writeDictionary(plist, to: infoURL)
            _ = try runner.run("/usr/bin/codesign", ["--remove-sign", instance.appPath], allowFailure: true)
            try runner.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", instance.appPath])
            try runner.run("/usr/bin/xattr", ["-cr", instance.appPath], allowFailure: true)
        }

        store.instances[index].name = name
        store.instances[index].updatedAt = Int64(Date().timeIntervalSince1970)
        try repository.save(store)
        if running {
            print("硬多开槽位菜单名已更新: \(id) -> \(name)。App 显示名会在下次重建后更新")
        } else {
            print("硬多开槽位已重命名: \(id) -> \(name)")
        }
    }

    func remove(id rawID: String, deleteApp: Bool) throws {
        var store = try repository.load()
        let id = try Identifier.normalizedInstanceID(rawID)
        let index = try indexOfInstance(id: id, in: store)
        let instance = store.instances[index]
        if try !runningProcesses(for: instance).isEmpty {
            try fail("硬多开槽位正在运行，请先 hard-stop \(id) 后再销毁")
        }
        if deleteApp, FileManager.default.fileExists(atPath: instance.appPath) {
            try FileManager.default.removeItem(atPath: instance.appPath)
        }
        store.instances.remove(at: index)
        try repository.save(store)
        print("硬多开槽位已销毁: \(id)")
    }

    func runningCount(id rawID: String) throws -> Int {
        let store = try repository.load()
        let id = try Identifier.normalizedInstanceID(rawID)
        let instance = try instance(id: id, in: store)
        return try runningMainProcesses(for: instance).count
    }

    private func resolvedAppPath(id: String, name: String, explicitPath: String?) throws -> String {
        if let explicitPath, !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: explicitPath).standardizedFileURL.path
        }
        let appName = try Identifier.appBundleName(defaultID: id, explicitName: name)
        return paths.hardAppRootDir.appendingPathComponent(appName).standardizedFileURL.path
    }

    private func indexOfInstance(id: String, in store: HardInstanceStore) throws -> Int {
        guard let index = store.instances.firstIndex(where: { $0.id == id }) else {
            try fail("硬多开槽位不存在: \(id)")
        }
        return index
    }

    private func instance(id: String, in store: HardInstanceStore) throws -> HardInstanceProfile {
        store.instances[try indexOfInstance(id: id, in: store)]
    }

    private func runningProcesses(for instance: HardInstanceProfile) throws -> [RunningProcess] {
        try runningMainProcesses(for: instance)
    }

    private func runningMainProcesses(for instance: HardInstanceProfile) throws -> [RunningProcess] {
        let appURL = URL(fileURLWithPath: instance.appPath).standardizedFileURL
        let executablePath = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WeChat")
            .path
        return try inspector.runningProcesses(executablePath: executablePath)
    }
}
