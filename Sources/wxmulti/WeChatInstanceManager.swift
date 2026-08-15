import Foundation

struct WeChatInstanceManager {
    private let runtimeResourcePaths = [
        "loader",
        "magic",
        "magicdy",
        "xplugin/info",
        "xplugin/config",
    ]
    private let runtimeResourceFiles = [
        "net/kvcomm/config.ini",
        "net/kvcomm/new_strategy_file_idkey",
        "net/kvcomm/new_strategy_file_kv",
    ]

    let paths: WxMultiPaths
    let repository: InstanceStoreRepository
    let runner: ProcessRunner
    let locator: WeChatLocator
    let entitlements: EntitlementsBuilder
    let inspector: ProcessInspector

    init(paths: WxMultiPaths = .defaults()) {
        let runner = ProcessRunner()
        self.paths = paths
        self.repository = InstanceStoreRepository(storeURL: paths.storeURL)
        self.runner = runner
        self.locator = WeChatLocator()
        self.entitlements = EntitlementsBuilder(runner: runner)
        self.inspector = ProcessInspector(runner: runner)
    }

    func doctor(sourcePath: String?) throws {
        try paths.ensureBaseDirectories()
        let info = try locator.resolve(sourcePath: sourcePath)
        print("微信路径: \(info.appURL.path)")
        print("Bundle ID: \(info.bundleIdentifier)")
        print("版本: \(info.shortVersion ?? "-") (\(info.bundleVersion ?? "-"))")
        print("实例配置: \(paths.storeURL.path)")
        print("分身目录: \(paths.appRootDir.path)")
        print("codesign: \(FileManager.default.fileExists(atPath: "/usr/bin/codesign") ? "可用" : "缺失")")
        print("open: \(FileManager.default.fileExists(atPath: "/usr/bin/open") ? "可用" : "缺失")")
        let sourceProcesses = try inspector.runningProcesses(executablePath: info.executableURL.path)
        print("原版微信进程: \(sourceProcesses.isEmpty ? "未运行" : "运行中 PID \(sourceProcesses.map { String($0.pid) }.joined(separator: ", "))")")
        _ = try entitlements.originalEntitlements(appURL: info.appURL)
        print("签名权限: 可读取")
    }

    func list() throws {
        let store = try repository.load()
        if store.instances.isEmpty {
            print("暂无实例")
            return
        }
        for instance in store.instances {
            let pid = try currentPID(for: instance)
            let status = pid.map { "运行中 PID \($0)" } ?? "未运行"
            let syncStatus = try syncStatus(for: instance, isRunning: pid != nil)
            print("\(instance.id)\t\(instance.name)\t\(status)\t\(syncStatus)\t\(instance.appPath)")
        }
    }

    func create(
        id rawID: String,
        name explicitName: String?,
        explicitBundleID: String?,
        appName explicitAppName: String?,
        sourcePath: String?,
        force: Bool,
        mode: EntitlementsMode
    ) throws {
        try paths.ensureBaseDirectories()
        let id = try Identifier.normalizedInstanceID(rawID)
        let source = try locator.resolve(sourcePath: sourcePath)
        let name = Identifier.displayName(defaultID: id, explicitName: explicitName)
        let bundleID = try Identifier.explicitBundleIdentifier(explicitBundleID) ??
            Identifier.bundleIdentifier(base: source.bundleIdentifier, instanceID: id)
        let appBundleName = try Identifier.appBundleName(defaultID: id, explicitName: explicitAppName)
        var targetAppURL = paths.appRootDir.appendingPathComponent(appBundleName, isDirectory: true)

        var store = try repository.load()
        if store.instances.contains(where: { $0.id == id }) && !force {
            try fail("实例已存在: \(id)。需要重建时请加 --force")
        }
        if FileManager.default.fileExists(atPath: targetAppURL.path) {
            if force {
                do {
                    try removeManagedApp(at: targetAppURL)
                } catch {
                    targetAppURL = versionedAppURL(for: id)
                    print("旧副本无法移除，将使用新路径: \(targetAppURL.path)")
                }
            } else {
                try fail("目标 App 已存在: \(targetAppURL.path)。需要覆盖时请加 --force")
            }
        }

        try buildAppCopy(
            id: id,
            source: source,
            targetAppURL: targetAppURL,
            bundleID: bundleID,
            name: name,
            mode: mode
        )

        var profile = InstanceProfile(
            id: id,
            name: name,
            bundleIdentifier: bundleID,
            appPath: targetAppURL.path,
            sourceAppPath: source.appURL.path,
            sourceShortVersion: source.shortVersion,
            sourceBundleVersion: source.bundleVersion,
            sourceFingerprint: try sourceFingerprint(for: source.appURL),
            sourceRuntimeFingerprint: nil,
            entitlementsMode: mode,
            createdAt: nowMillis(),
            lastLaunchedAt: nil,
            lastPid: nil
        )
        profile.sourceRuntimeFingerprint = try syncRuntime(instance: profile, source: source, announce: true)
        store.instances.removeAll { $0.id == id }
        store.instances.append(profile)
        store.instances.sort { $0.id < $1.id }
        try repository.save(store)
        print("实例已创建: \(id)")
        print("App 路径: \(targetAppURL.path)")
    }

    func rebuild(id rawID: String) throws {
        let id = try Identifier.normalizedInstanceID(rawID)
        var store = try repository.load()
        guard let index = store.instances.firstIndex(where: { $0.id == id }) else {
            try fail("实例不存在: \(id)")
        }
        var instance = store.instances[index]
        if try currentPID(for: instance) != nil {
            try fail("实例正在运行，请先 stop 后再重建")
        }
        let source = try locator.resolve(sourcePath: instance.sourceAppPath)
        print("正在重建实例: \(id)")
        instance = try rebuildProfile(instance, source: source)
        instance.sourceRuntimeFingerprint = try syncRuntime(instance: instance, source: source, announce: true)
        store.instances[index] = instance
        try repository.save(store)
        print("实例已重建: \(id)")
    }

    func start(id rawID: String) throws {
        let id = try Identifier.normalizedInstanceID(rawID)
        var store = try repository.load()
        guard let index = store.instances.firstIndex(where: { $0.id == id }) else {
            try fail("实例不存在: \(id)")
        }
        var instance = store.instances[index]
        if let pid = try currentPID(for: instance) {
            print("实例已在运行: \(id) PID \(pid)")
            if try shouldSyncRuntime(instance: instance, source: locator.resolve(sourcePath: instance.sourceAppPath)) {
                print("运行资源已有更新，请先 stop 再 start 以完成同步")
            }
            return
        }
        let source = try locator.resolve(sourcePath: instance.sourceAppPath)
        if try shouldRebuild(instance: instance, source: source) {
            print("检测到微信已更新，正在自动重建实例...")
            instance = try rebuildProfile(instance, source: source)
            store.instances[index] = instance
            try repository.save(store)
        }
        if try shouldSyncRuntime(instance: instance, source: source) {
            instance.sourceRuntimeFingerprint = try syncRuntime(instance: instance, source: source, announce: true)
        }
        try prepareAppForLaunch(instance: instance, source: source)
        let appURL = URL(fileURLWithPath: instance.appPath)
        try FileManager.default.createDirectory(
            at: containerDataURL(bundleIdentifier: instance.bundleIdentifier).appendingPathComponent("tmp", isDirectory: true),
            withIntermediateDirectories: true
        )
        try runner.run("/usr/bin/open", ["-n"] + openEnvironmentArguments(bundleIdentifier: instance.bundleIdentifier) + [appURL.path])
        let pid = try waitForPID(appURL: appURL, executableName: "WeChat", timeoutSeconds: 15)
        store.instances[index] = instance
        store.instances[index].lastLaunchedAt = nowMillis()
        store.instances[index].lastPid = pid
        try repository.save(store)
        if let pid {
            print("实例已启动: \(id) PID \(pid)")
        } else {
            print("启动命令已发送: \(id)")
        }
    }

    func stop(id rawID: String) throws {
        let id = try Identifier.normalizedInstanceID(rawID)
        var store = try repository.load()
        guard let index = store.instances.firstIndex(where: { $0.id == id }) else {
            try fail("实例不存在: \(id)")
        }
        let instance = store.instances[index]
        let processes = try runningMainProcesses(for: instance)
        guard !processes.isEmpty else {
            store.instances[index].lastPid = nil
            try repository.save(store)
            print("实例未运行: \(id)")
            return
        }
        for process in processes {
            try runner.run("/bin/kill", ["-TERM", "\(process.pid)"], allowFailure: true)
        }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if processes.allSatisfy({ !inspector.isRunning($0.pid) }) {
                store.instances[index].lastPid = nil
                try repository.save(store)
                print("实例已关闭: \(id)")
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        for process in processes {
            try runner.run("/bin/kill", ["-KILL", "\(process.pid)"], allowFailure: true)
        }
        store.instances[index].lastPid = nil
        try repository.save(store)
        print("实例已强制关闭: \(id)")
    }

    func syncRuntime(id rawID: String) throws {
        let id = try Identifier.normalizedInstanceID(rawID)
        var store = try repository.load()
        guard let index = store.instances.firstIndex(where: { $0.id == id }) else {
            try fail("实例不存在: \(id)")
        }
        var instance = store.instances[index]
        if try currentPID(for: instance) != nil {
            try fail("实例正在运行，请先 stop 后再同步运行资源")
        }
        let source = try locator.resolve(sourcePath: instance.sourceAppPath)
        instance.sourceRuntimeFingerprint = try syncRuntime(instance: instance, source: source, announce: true)
        store.instances[index] = instance
        try repository.save(store)
    }

    func rename(id rawID: String, name explicitName: String) throws {
        let id = try Identifier.normalizedInstanceID(rawID)
        var store = try repository.load()
        guard let index = store.instances.firstIndex(where: { $0.id == id }) else {
            try fail("实例不存在: \(id)")
        }
        let name = Identifier.displayName(defaultID: id, explicitName: explicitName)
        var instance = store.instances[index]
        instance.name = name
        let appURL = URL(fileURLWithPath: instance.appPath)
        if FileManager.default.fileExists(atPath: appURL.path) {
            if try currentPID(for: instance) == nil {
                let source = try locator.resolve(sourcePath: instance.sourceAppPath)
                try rewriteMainInfoPlist(appURL: appURL, bundleID: instance.bundleIdentifier, name: name)
                try rewriteNestedAppBundleIdentifiers(appURL: appURL, id: instance.id)
                try signApp(
                    id: instance.id,
                    sourceAppURL: source.appURL,
                    targetAppURL: appURL,
                    bundleID: instance.bundleIdentifier,
                    mode: instance.entitlementsMode
                )
            } else {
                print("实例正在运行，菜单备注已更新；App 显示名将在下次重建后更新")
            }
        }
        store.instances[index] = instance
        try repository.save(store)
        print("实例备注已更新: \(id) -> \(name)")
    }

    func profiles() throws -> [InstanceProfile] {
        try repository.load().instances
    }

    private func syncRuntime(instance: InstanceProfile, source: WeChatAppInfo, announce: Bool) throws -> String? {
        let fingerprint = try sourceRuntimeFingerprint(for: source)
        let sourceContainer = appDataContainer(bundleIdentifier: source.bundleIdentifier)
        let targetContainer = appDataContainer(bundleIdentifier: instance.bundleIdentifier)

        for relative in runtimeResourcePaths {
            let sourceURL = sourceContainer.appendingPathComponent(relative, isDirectory: true)
            let targetURL = targetContainer.appendingPathComponent(relative, isDirectory: true)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                continue
            }
            try copyDirectory(from: sourceURL, to: targetURL, removeTargetFirst: true)
            if announce {
                print("已同步: \(relative)")
            }
        }
        for relative in runtimeResourceFiles {
            let sourceURL = sourceContainer.appendingPathComponent(relative)
            let targetURL = targetContainer.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                continue
            }
            try copyFile(from: sourceURL, to: targetURL)
            if announce {
                print("已同步: \(relative)")
            }
        }
        if announce {
            print("运行资源同步完成: \(instance.id)")
        }
        return fingerprint
    }

    func remove(id rawID: String, deleteApp: Bool) throws {
        let id = try Identifier.normalizedInstanceID(rawID)
        var store = try repository.load()
        guard let index = store.instances.firstIndex(where: { $0.id == id }) else {
            try fail("实例不存在: \(id)")
        }
        let instance = store.instances[index]
        if try currentPID(for: instance) != nil {
            try fail("实例正在运行，请先 stop 后再删除")
        }
        if deleteApp {
            try removeManagedApp(at: URL(fileURLWithPath: instance.appPath))
        }
        store.instances.remove(at: index)
        try repository.save(store)
        print("实例记录已删除: \(id)")
    }

    private func rewriteMainInfoPlist(appURL: URL, bundleID: String, name _: String) throws {
        let infoURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        var plist = try PlistEditor.readDictionary(infoURL)
        plist["CFBundleIdentifier"] = bundleID
        try PlistEditor.writeDictionary(plist, to: infoURL)
    }

    private func buildAppCopy(
        id: String,
        source: WeChatAppInfo,
        targetAppURL: URL,
        bundleID: String,
        name: String,
        mode: EntitlementsMode
    ) throws {
        print("正在复制微信副本...")
        try runner.run("/usr/bin/ditto", [source.appURL.path, targetAppURL.path])
        try runner.run("/bin/chmod", ["-R", "u+rwX", targetAppURL.path], allowFailure: true)
        try runner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", targetAppURL.path], allowFailure: true)
        try rewriteMainInfoPlist(appURL: targetAppURL, bundleID: bundleID, name: name)
        try rewriteNestedAppBundleIdentifiers(appURL: targetAppURL, id: id)
        try installLaunchWrapper(appURL: targetAppURL, bundleID: bundleID, source: source)
        try installFrameworkHelperWrappers(appURL: targetAppURL, bundleID: bundleID, source: source)

        print("正在重新签名...")
        try signApp(
            id: id,
            sourceAppURL: source.appURL,
            targetAppURL: targetAppURL,
            bundleID: bundleID,
            mode: mode
        )
    }

    private func signApp(
        id: String,
        sourceAppURL: URL,
        targetAppURL: URL,
        bundleID: String,
        mode: EntitlementsMode
    ) throws {
        let entitlementURL = paths.entitlementsDir.appendingPathComponent("\(id).plist")
        try entitlements.writeEntitlements(
            sourceAppURL: sourceAppURL,
            targetBundleID: bundleID,
            mode: mode,
            to: entitlementURL
        )

        if mode == .none {
            try runner.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", targetAppURL.path])
        } else {
            try runner.run("/usr/bin/codesign", [
                "--force",
                "--deep",
                "--sign",
                "-",
                "--entitlements",
                entitlementURL.path,
                targetAppURL.path,
            ])
        }
    }

    private func prepareAppForLaunch(instance: InstanceProfile, source: WeChatAppInfo) throws {
        let appURL = URL(fileURLWithPath: instance.appPath)
        var changed = try rewriteNestedAppBundleIdentifiers(appURL: appURL, id: instance.id)
        if try restoreMainExecutableIfWrapped(appURL: appURL) {
            changed = true
        }
        if try installLaunchWrapper(appURL: appURL, bundleID: instance.bundleIdentifier, source: source) {
            changed = true
        }
        if try installFrameworkHelperWrappers(appURL: appURL, bundleID: instance.bundleIdentifier, source: source) {
            changed = true
        }
        if changed {
            try signApp(
                id: instance.id,
                sourceAppURL: source.appURL,
                targetAppURL: appURL,
                bundleID: instance.bundleIdentifier,
                mode: instance.entitlementsMode
            )
        }
    }

    @discardableResult
    private func rewriteNestedAppBundleIdentifiers(appURL: URL, id: String) throws -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [],
            errorHandler: nil
        ) else {
            return false
        }

        let executableBundleExtensions: Set<String> = ["app", "appex", "xpc"]
        var changed = false
        for case let infoURL as URL in enumerator where infoURL.lastPathComponent == "Info.plist" {
            let contentsURL = infoURL.deletingLastPathComponent()
            let nestedAppURL = contentsURL.deletingLastPathComponent()
            guard contentsURL.lastPathComponent == "Contents",
                  executableBundleExtensions.contains(nestedAppURL.pathExtension),
                  nestedAppURL.standardizedFileURL.path != appURL.standardizedFileURL.path else {
                continue
            }
            var plist = try PlistEditor.readDictionary(infoURL)
            guard let current = PlistEditor.stringValue(plist, "CFBundleIdentifier"),
                  current.hasPrefix("com.tencent.") else {
                continue
            }
            let base = current.components(separatedBy: ".wxmulti.").first ?? current
            let target = Identifier.bundleIdentifier(base: base, instanceID: id)
            guard current != target else {
                continue
            }
            plist["CFBundleIdentifier"] = target
            try PlistEditor.writeDictionary(plist, to: infoURL)
            changed = true
        }
        return changed
    }

    private func openEnvironmentArguments(bundleIdentifier: String) -> [String] {
        let containerDataPath = containerDataURL(bundleIdentifier: bundleIdentifier).path
        var environment = [
            "__CFBundleIdentifier": bundleIdentifier,
            "HOME": containerDataPath,
            "CFFIXED_USER_HOME": containerDataPath,
            "TMPDIR": "\(containerDataPath)/tmp/",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        let inherited = ProcessInfo.processInfo.environment
        for key in ["LOGNAME", "USER", "SHELL", "__CF_USER_TEXT_ENCODING"] {
            if let value = inherited[key] {
                environment[key] = value
            }
        }
        return environment
            .sorted { $0.key < $1.key }
            .flatMap { ["--env", "\($0.key)=\($0.value)"] }
    }

    @discardableResult
    private func restoreMainExecutableIfWrapped(appURL: URL) throws -> Bool {
        let executableURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WeChat")
        let macOSURL = executableURL.deletingLastPathComponent()
        let realDirURL = macOSURL.appendingPathComponent("WeChat.real", isDirectory: true)
        let realURL = realDirURL.appendingPathComponent("WeChat")
        let legacyRealURL = macOSURL.appendingPathComponent("WeChat.real")
        let frameworkLinkURL = macOSURL.appendingPathComponent("Frameworks")
        let manager = FileManager.default
        var changed = false

        if manager.fileExists(atPath: realURL.path) {
            if manager.fileExists(atPath: executableURL.path) {
                try manager.removeItem(at: executableURL)
            }
            try manager.moveItem(at: realURL, to: executableURL)
            try? manager.removeItem(at: realDirURL)
            changed = true
        }

        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: legacyRealURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            if manager.fileExists(atPath: executableURL.path) {
                try manager.removeItem(at: executableURL)
            }
            try manager.moveItem(at: legacyRealURL, to: executableURL)
            changed = true
        }

        if (try? frameworkLinkURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try manager.removeItem(at: frameworkLinkURL)
            changed = true
        }
        return changed
    }

    @discardableResult
    private func installFrameworkHelperWrappers(appURL: URL, bundleID: String, source: WeChatAppInfo) throws -> Bool {
        let frameworksURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Frameworks", isDirectory: true)
        let helperNames = ["wxocr", "wxplayer", "wxutility"]
        let containerDataPath = containerDataURL(bundleIdentifier: bundleID).path
        let runtimeBundleIdentifier = try sourceLaunchProfile(source: source).runtimeBundleIdentifier ?? ""
        var changed = false
        for name in helperNames {
            let executableURL = frameworksURL.appendingPathComponent(name)
            let realURL = frameworksURL.appendingPathComponent("\(name).real")
            guard FileManager.default.fileExists(atPath: executableURL.path) ||
                    FileManager.default.fileExists(atPath: realURL.path) else {
                continue
            }
            if !FileManager.default.fileExists(atPath: realURL.path) {
                try FileManager.default.moveItem(at: executableURL, to: realURL)
                changed = true
            }
            let script = frameworkHelperWrapperScript(
                realPath: realURL.path,
                containerDataPath: containerDataPath,
                runtimeBundleIdentifier: runtimeBundleIdentifier
            )
            let existing = try? String(contentsOf: executableURL, encoding: .utf8)
            if existing != script {
                try script.write(to: executableURL, atomically: true, encoding: .utf8)
                try runner.run("/bin/chmod", ["755", executableURL.path])
                changed = true
            }
        }
        return changed
    }

    private func frameworkHelperWrapperScript(
        realPath: String,
        containerDataPath: String,
        runtimeBundleIdentifier: String
    ) -> String {
        """
        #!/bin/zsh
        set -u

        CONTAINER_DATA="\(shellLiteral(containerDataPath))"
        RUNTIME_BUNDLE_ID="\(shellLiteral(runtimeBundleIdentifier))"
        REAL="\(shellLiteral(realPath))"

        /bin/mkdir -p "$CONTAINER_DATA/tmp"
        export HOME="$CONTAINER_DATA"
        export CFFIXED_USER_HOME="$CONTAINER_DATA"
        export TMPDIR="$CONTAINER_DATA/tmp/"
        export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
        cd "$CONTAINER_DATA" || exit 1

        args=()
        for arg in "$@"; do
          if [[ -n "$RUNTIME_BUNDLE_ID" && "$arg" == --base-bundle-id=* ]]; then
            arg="--base-bundle-id=$RUNTIME_BUNDLE_ID"
          fi
          args+=("$arg")
        done

        exec -a "${0:A}" "$REAL" "${args[@]}"
        """
    }

    @discardableResult
    private func installLaunchWrapper(appURL: URL, bundleID: String, source: WeChatAppInfo) throws -> Bool {
        let executableURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WeChatAppEx.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WeChatAppEx")
        let macOSURL = executableURL.deletingLastPathComponent()
        let contentsURL = macOSURL.deletingLastPathComponent()
        let realDirURL = macOSURL.appendingPathComponent("WeChatAppEx.real", isDirectory: true)
        let realURL = realDirURL.appendingPathComponent("WeChatAppEx")
        let legacyRealURL = macOSURL.appendingPathComponent("WeChatAppEx.real")
        let legacyRealDirURL = contentsURL
            .appendingPathComponent("MacOS.real", isDirectory: true)
            .appendingPathComponent("WeChatAppEx")
        let frameworkLinkURL = macOSURL.appendingPathComponent("Frameworks")
        let manager = FileManager.default
        var changed = false
        if !manager.fileExists(atPath: realURL.path) {
            try manager.createDirectory(at: realDirURL, withIntermediateDirectories: true)
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: legacyRealURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                try manager.moveItem(at: legacyRealURL, to: realURL)
                changed = true
            } else if manager.fileExists(atPath: legacyRealDirURL.path) {
                try manager.moveItem(at: legacyRealDirURL, to: realURL)
                try? manager.removeItem(at: legacyRealDirURL.deletingLastPathComponent())
                changed = true
            } else if manager.fileExists(atPath: executableURL.path) {
                try manager.moveItem(at: executableURL, to: realURL)
                changed = true
            } else {
                try fail("缺少 WeChatAppEx 可执行文件: \(executableURL.path)")
            }
        }
        if !manager.fileExists(atPath: frameworkLinkURL.path) {
            try manager.createSymbolicLink(atPath: frameworkLinkURL.path, withDestinationPath: "../Frameworks")
            changed = true
        }
        let profile = try sourceLaunchProfile(source: source)
        let script = launchWrapperScript(
            profile: profile,
            containerDataPath: containerDataURL(bundleIdentifier: bundleID).path
        )
        let existing = try? String(contentsOf: executableURL, encoding: .utf8)
        if existing != script {
            try script.write(to: executableURL, atomically: true, encoding: .utf8)
            try runner.run("/bin/chmod", ["755", executableURL.path])
            changed = true
        }
        return changed
    }

    private func launchWrapperScript(profile: LaunchProfile, containerDataPath: String) -> String {
        """
        #!/bin/zsh
        set -u

        CONTAINER_DATA="\(shellLiteral(containerDataPath))"
        CLIENT_VERSION="\(shellLiteral(profile.clientVersion ?? ""))"
        UNIFIED_VERSION="\(shellLiteral(profile.unifiedPCMacWechat ?? ""))"
        RUNTIME_BUNDLE_ID="\(shellLiteral(profile.runtimeBundleIdentifier ?? ""))"
        REAL="${0:A:h}/WeChatAppEx.real/WeChatAppEx"

        /bin/mkdir -p "$CONTAINER_DATA/tmp"
        export HOME="$CONTAINER_DATA"
        export CFFIXED_USER_HOME="$CONTAINER_DATA"
        export TMPDIR="$CONTAINER_DATA/tmp/"
        export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
        cd "${0:A:h}" || exit 1

        args=()
        for arg in "$@"; do
          if [[ -n "$CLIENT_VERSION" && "$arg" == --client_version=* ]]; then
            arg="--client_version=$CLIENT_VERSION"
          fi
          if [[ -n "$RUNTIME_BUNDLE_ID" && "$arg" == --bundle-id=* ]]; then
            arg="--bundle-id=$RUNTIME_BUNDLE_ID"
          fi
          if [[ -n "$UNIFIED_VERSION" && "$arg" == --wechat-sub-user-agent=* ]]; then
            arg="$(/usr/bin/sed -E "s/UnifiedPCMacWechat\\(0x[0-9A-Fa-f]+\\)/UnifiedPCMacWechat(${UNIFIED_VERSION})/g" <<< "$arg")"
          fi
          args+=("$arg")
        done

        exec -a "${0:A}" "$REAL" "${args[@]}"
        """
    }

    private func sourceLaunchProfile(source: WeChatAppInfo) throws -> LaunchProfile {
        let sourceAppExPath = source.appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WeChatAppEx.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WeChatAppEx")
            .path
        let result = try runner.run("/bin/ps", ["-axww", "-o", "command="])
        let command = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first { line in
                line.contains(sourceAppExPath) &&
                line.contains("--client_version=") &&
                line.contains("UnifiedPCMacWechat(")
            }
        var profile = command.map(parseLaunchProfile(command:)) ?? LaunchProfile(
            clientVersion: nil,
            unifiedPCMacWechat: nil,
            runtimeBundleIdentifier: nil
        )
        if profile.clientVersion == nil {
            profile.clientVersion = try runtimeClientVersion(source: source)
        }
        if profile.unifiedPCMacWechat == nil, let clientVersion = profile.clientVersion, let version = UInt32(clientVersion) {
            profile.unifiedPCMacWechat = "0x" + String(version, radix: 16)
        }
        if profile.runtimeBundleIdentifier == nil {
            profile.runtimeBundleIdentifier = try signedRuntimeBundleIdentifier(source: source)
        }
        return profile
    }

    private func parseLaunchProfile(command: String) -> LaunchProfile {
        LaunchProfile(
            clientVersion: firstMatch(in: command, pattern: "--client_version=([0-9]+)"),
            unifiedPCMacWechat: firstMatch(in: command, pattern: "UnifiedPCMacWechat\\((0x[0-9A-Fa-f]+)\\)"),
            runtimeBundleIdentifier: firstMatch(in: command, pattern: "--bundle-id=([^\\s]+)")
        )
    }

    private func runtimeClientVersion(source: WeChatAppInfo) throws -> String? {
        let configURL = appDataContainer(bundleIdentifier: source.bundleIdentifier)
            .appendingPathComponent("net", isDirectory: true)
            .appendingPathComponent("kvcomm", isDirectory: true)
            .appendingPathComponent("config.ini")
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }
        return firstMatch(in: content, pattern: "kv_clientversion=([0-9]+)") ??
            firstMatch(in: content, pattern: "idkey_clientversion=([0-9]+)")
    }

    private func signedRuntimeBundleIdentifier(source: WeChatAppInfo) throws -> String? {
        let result = try runner.run("/usr/bin/codesign", ["-dv", source.appURL.path], allowFailure: true)
        let output = result.stdout + "\n" + result.stderr
        guard let teamID = firstMatch(in: output, pattern: "TeamIdentifier=([^\\s]+)") else {
            return nil
        }
        return "\(teamID).\(source.bundleIdentifier)"
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }

    private func shellLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    private func rebuildProfile(_ instance: InstanceProfile, source: WeChatAppInfo) throws -> InstanceProfile {
        var targetAppURL = URL(fileURLWithPath: instance.appPath)
        if FileManager.default.fileExists(atPath: targetAppURL.path) {
            do {
                try removeManagedApp(at: targetAppURL)
            } catch {
                targetAppURL = versionedAppURL(for: instance.id)
                print("旧副本无法移除，将使用新路径: \(targetAppURL.path)")
            }
        }
        try buildAppCopy(
            id: instance.id,
            source: source,
            targetAppURL: targetAppURL,
            bundleID: instance.bundleIdentifier,
            name: instance.name,
            mode: instance.entitlementsMode
        )
        var updated = instance
        updated.appPath = targetAppURL.path
        updated.sourceAppPath = source.appURL.path
        updated.sourceShortVersion = source.shortVersion
        updated.sourceBundleVersion = source.bundleVersion
        updated.sourceFingerprint = try sourceFingerprint(for: source.appURL)
        updated.lastPid = nil
        return updated
    }

    private func versionedAppURL(for id: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return paths.appRootDir.appendingPathComponent(
            "WeChat-\(id)-\(formatter.string(from: Date())).app",
            isDirectory: true
        )
    }

    private func shouldRebuild(instance: InstanceProfile, source: WeChatAppInfo) throws -> Bool {
        let appURL = URL(fileURLWithPath: instance.appPath)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return true
        }
        let current = try sourceFingerprint(for: source.appURL)
        return instance.sourceFingerprint != current
    }

    private func shouldSyncRuntime(instance: InstanceProfile, source: WeChatAppInfo) throws -> Bool {
        let current = try sourceRuntimeFingerprint(for: source)
        return instance.sourceRuntimeFingerprint != current
    }

    private func syncStatus(for instance: InstanceProfile, isRunning: Bool) throws -> String {
        let source = try locator.resolve(sourcePath: instance.sourceAppPath)
        if try shouldRebuild(instance: instance, source: source) {
            return "需重建"
        }
        if try shouldSyncRuntime(instance: instance, source: source) {
            return isRunning ? "运行资源待重启同步" : "运行资源需同步"
        }
        return "已同步"
    }

    private func sourceFingerprint(for appURL: URL) throws -> String {
        let candidates = [
            appURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("WeChat"),
            appURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("WeChatAppEx.app", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("WeChatAppEx"),
        ]
        var parts: [String] = []
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let result = try runner.run("/usr/bin/shasum", ["-a", "256", url.path])
            let hash = result.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size].map { "\($0)" } ?? "0"
            parts.append("\(url.lastPathComponent):\(size):\(hash)")
        }
        if parts.isEmpty {
            try fail("无法生成微信 App 指纹: \(appURL.path)")
        }
        return parts.joined(separator: "|")
    }

    private func sourceRuntimeFingerprint(for source: WeChatAppInfo) throws -> String? {
        try runtimeFingerprint(appDataURL: appDataContainer(bundleIdentifier: source.bundleIdentifier))
    }

    private func containerDataURL(bundleIdentifier: String) -> URL {
        paths.home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    private func appDataContainer(bundleIdentifier: String) -> URL {
        containerDataURL(bundleIdentifier: bundleIdentifier)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("app_data", isDirectory: true)
    }

    private func runtimeFingerprint(appDataURL: URL) throws -> String? {
        let manager = FileManager.default
        var entries: [String] = []
        for relative in runtimeResourcePaths {
            let root = appDataURL.appendingPathComponent(relative, isDirectory: true)
            guard manager.fileExists(atPath: root.path) else {
                continue
            }
            entries.append("dir:\(relative)")
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
                continue
            }
            let files = enumerator
                .compactMap { $0 as? URL }
                .filter { $0.lastPathComponent != ".DS_Store" }
                .filter { url in
                    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                }
                .sorted { $0.path < $1.path }
            let rootPath = root.standardizedFileURL.path
            for fileURL in files {
                let result = try runner.run("/usr/bin/shasum", ["-a", "256", fileURL.path])
                let hash = result.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                let size = values.fileSize.map(String.init) ?? "0"
                let relativeFilePath = String(fileURL.standardizedFileURL.path.dropFirst(rootPath.count + 1))
                entries.append("file:\(relative)/\(relativeFilePath):\(size):\(hash)")
            }
        }
        for relative in runtimeResourceFiles {
            let fileURL = appDataURL.appendingPathComponent(relative)
            guard manager.fileExists(atPath: fileURL.path) else {
                continue
            }
            let result = try runner.run("/usr/bin/shasum", ["-a", "256", fileURL.path])
            let hash = result.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = values.fileSize.map(String.init) ?? "0"
            entries.append("file:\(relative):\(size):\(hash)")
        }
        return entries.isEmpty ? nil : entries.joined(separator: "|")
    }

    private func removeManagedApp(at appURL: URL) throws {
        let root = paths.appRootDir.standardizedFileURL.path
        let target = appURL.standardizedFileURL.path
        guard target.hasPrefix(root + "/") else {
            try fail("拒绝删除非托管目录: \(target)")
        }
        if FileManager.default.fileExists(atPath: target) {
            try runner.run("/bin/chmod", ["-R", "a+rwX", target], allowFailure: true)
            let result = try runner.run("/bin/rm", ["-rf", target], allowFailure: true)
            if result.status != 0, FileManager.default.fileExists(atPath: target) {
                try retireManagedApp(at: appURL)
            }
        }
        if FileManager.default.fileExists(atPath: target) {
            try fail("删除托管 App 失败: \(target)")
        }
    }

    private func retireManagedApp(at appURL: URL) throws {
        try paths.ensureBaseDirectories()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let retiredName = "\(appURL.deletingPathExtension().lastPathComponent)-\(formatter.string(from: Date())).app"
        let retiredURL = paths.staleAppDir.appendingPathComponent(retiredName, isDirectory: true)
        try FileManager.default.moveItem(at: appURL, to: retiredURL)
        print("旧副本权限受限，已移入: \(retiredURL.path)")
    }

    private func copyDirectory(from sourceURL: URL, to targetURL: URL, removeTargetFirst: Bool) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if removeTargetFirst, manager.fileExists(atPath: targetURL.path) {
            try manager.removeItem(at: targetURL)
        }
        if manager.fileExists(atPath: targetURL.path) {
            let entries = try manager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
            for entry in entries {
                let childTarget = targetURL.appendingPathComponent(entry.lastPathComponent)
                if manager.fileExists(atPath: childTarget.path) {
                    try manager.removeItem(at: childTarget)
                }
                try manager.copyItem(at: entry, to: childTarget)
            }
        } else {
            try manager.copyItem(at: sourceURL, to: targetURL)
        }
    }

    private func copyFile(from sourceURL: URL, to targetURL: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: targetURL.path) {
            try manager.removeItem(at: targetURL)
        }
        try manager.copyItem(at: sourceURL, to: targetURL)
    }

    private func currentPID(for instance: InstanceProfile) throws -> Int32? {
        try runningMainProcesses(for: instance).first?.pid
    }

    private func runningMainProcesses(for instance: InstanceProfile) throws -> [RunningProcess] {
        let appURL = URL(fileURLWithPath: instance.appPath)
        let executablePath = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WeChat")
            .path
        return try inspector.runningProcesses(executablePath: executablePath)
    }

    private func waitForPID(appURL: URL, executableName: String, timeoutSeconds: TimeInterval) throws -> Int32? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let pid = try inspector.firstPID(for: appURL, executableName: executableName) {
                return pid
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    private func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
