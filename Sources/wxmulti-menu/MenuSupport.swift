import AppKit
import Foundation

struct MenuInstance: Decodable {
    let id: String
    let name: String
    let appPath: String
    let bundleIdentifier: String
}

struct MenuStore: Decodable {
    let instances: [MenuInstance]
}

struct AccountAlias: Codable, Equatable {
    var name: String?
    var wechatID: String?

    static func cleaned(name: String, wechatID: String) -> AccountAlias? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWechatID = wechatID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty || !cleanWechatID.isEmpty else {
            return nil
        }
        return AccountAlias(
            name: cleanName.isEmpty ? nil : cleanName,
            wechatID: cleanWechatID.isEmpty ? nil : cleanWechatID
        )
    }

    var label: String? {
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWechatID = wechatID?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (cleanName?.isEmpty == false ? cleanName : nil, cleanWechatID?.isEmpty == false ? cleanWechatID : nil) {
        case let (.some(name), .some(wechatID)) where name != wechatID:
            return "\(name) · \(wechatID)"
        case let (.some(name), _):
            return name
        case let (_, .some(wechatID)):
            return wechatID
        default:
            return nil
        }
    }
}

final class InstanceReference: NSObject {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

final class CLI: @unchecked Sendable {
    private let executableURL: URL
    private let workingDirectory: URL

    init() {
        let argv0 = URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = argv0.deletingLastPathComponent().appendingPathComponent("wxmulti")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            executableURL = sibling
            workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
    }

    @discardableResult
    func run(_ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = workingDirectory
        process.arguments = executableURL.lastPathComponent == "swift"
            ? ["run", "wxmulti"] + args
            : args
        if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = devNull
            process.standardError = devNull
        }
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct RunningAppSnapshot: Equatable, Sendable {
    static let empty = RunningAppSnapshot(pidsByAppPath: [:])

    var pidsByAppPath: [String: [Int32]]

    func pids(for appPath: String) -> [Int32] {
        pidsByAppPath[appPath] ?? []
    }

    func count(for appPath: String) -> Int {
        pids(for: appPath).count
    }

    func contains(_ appPath: String) -> Bool {
        count(for: appPath) > 0
    }
}

final class ProcessStatus: @unchecked Sendable {
    @MainActor
    func runningSnapshot(appPaths: [String]) -> RunningAppSnapshot {
        guard !appPaths.isEmpty else {
            return .empty
        }
        let appPathByExecutablePath = Dictionary(uniqueKeysWithValues: appPaths.map { appPath in
            let executable = URL(fileURLWithPath: appPath)
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("WeChat")
                .standardizedFileURL
                .path
            return (executable, appPath)
        })
        var pidsByAppPath: [String: Set<Int32>] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let executablePath = app.executableURL?.standardizedFileURL.path else {
                continue
            }
            if let appPath = appPathByExecutablePath[executablePath] {
                pidsByAppPath[appPath, default: []].insert(app.processIdentifier)
            }
        }
        return RunningAppSnapshot(
            pidsByAppPath: pidsByAppPath.mapValues { $0.sorted() }
        )
    }
}

final class SystemOpener: @unchecked Sendable {
    @discardableResult
    func open(_ path: String) -> Bool {
        runOpen([path])
    }

    @discardableResult
    func activateApplication(at path: String) -> Bool {
        runOpen(["-a", path])
    }

    @discardableResult
    func activateApplication(bundleIdentifier: String) -> Bool {
        runOpen(["-b", bundleIdentifier])
    }

    @discardableResult
    func reveal(_ path: String) -> Bool {
        runOpen(["-R", path])
    }

    @discardableResult
    func openParent(of path: String) -> Bool {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return runOpen([parent])
    }

    private func runOpen(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = devNull
            process.standardError = devNull
        }
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct OfficialWeChatApp {
    static let sourcePath = "/Applications/WeChat.app"
    static let bundleIdentifier = "com.tencent.xinWeChat"
}

final class StoreReader {
    private let storeURL: URL

    init() {
        let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("WxMulti", isDirectory: true)
        storeURL = appSupportDir.appendingPathComponent("instances.json")
    }

    func read() -> [MenuInstance] {
        guard let data = try? Data(contentsOf: storeURL) else {
            return []
        }
        return (try? JSONDecoder().decode(MenuStore.self, from: data).instances) ?? []
    }
}

final class AccountAliasStore {
    private let aliasesURL: URL

    init(aliasesURL: URL? = nil) {
        let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("WxMulti", isDirectory: true)
        self.aliasesURL = aliasesURL ?? appSupportDir.appendingPathComponent("account-aliases.json")
    }

    func read() -> [String: AccountAlias] {
        (try? readForEditing()) ?? [:]
    }

    @discardableResult
    func update(accountID: String, name: String, wechatID: String) throws -> [String: AccountAlias] {
        guard accountID.hasPrefix("wxid_") else {
            throw NSError(domain: "AccountAliasStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "只能编辑 wxid_ 账号",
            ])
        }
        var aliases = try readForEditing()
        if let alias = AccountAlias.cleaned(name: name, wechatID: wechatID) {
            aliases[accountID] = alias
        } else {
            aliases.removeValue(forKey: accountID)
        }
        try write(aliases)
        return aliases
    }

    private func readForEditing() throws -> [String: AccountAlias] {
        guard FileManager.default.fileExists(atPath: aliasesURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: aliasesURL)
        do {
            return try JSONDecoder().decode([String: AccountAlias].self, from: data)
        } catch {
            throw NSError(domain: "AccountAliasStore", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "账号别名文件不是有效 JSON",
                NSUnderlyingErrorKey: error,
            ])
        }
    }

    private func write(_ aliases: [String: AccountAlias]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(aliases)
        try FileManager.default.createDirectory(
            at: aliasesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: aliasesURL, options: .atomic)
    }
}

struct CachedStorageSize: Codable, Equatable {
    var dataBytes: UInt64
    var updatedAt: Int64
}

final class StorageSizeCache {
    private let cacheURL: URL

    init(cacheURL: URL? = nil) {
        let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("WxMulti", isDirectory: true)
        self.cacheURL = cacheURL ?? appSupportDir.appendingPathComponent("storage-cache.json")
    }

    func read() -> [String: CachedStorageSize] {
        guard let data = try? Data(contentsOf: cacheURL) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: CachedStorageSize].self, from: data)) ?? [:]
    }

    func write(_ cache: [String: CachedStorageSize]) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: [.atomic])
        } catch {
            // 缓存失败不影响核心功能。
        }
    }
}
