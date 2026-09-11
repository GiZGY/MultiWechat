import AppKit
import Foundation

struct StorageAccountRecord: Equatable {
    var id: String
    var modifiedAt: Date
}

struct StorageItem: Equatable {
    var id: String
    var title: String
    var bundleIdentifier: String
    var appPath: String?
    var containerPath: String
    var containerExists: Bool
    var dataBytes: UInt64
    var isDataSizeKnown: Bool
    var accounts: [StorageAccountRecord]
    var activeAccountID: String?
    var isOriginal: Bool
    var isRunning: Bool

    var latestAccountID: String? {
        activeAccountID ?? accounts.max(by: { $0.modifiedAt < $1.modifiedAt })?.id
    }
}

final class StorageInspector: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let accountCacheLock = NSLock()
    private var accountCache = AccountLookupCache()

    func scan(instances: [MenuInstance], runningSnapshot: RunningAppSnapshot, includeDataSizes: Bool) -> [StorageItem] {
        var items = [
            item(
                id: "official",
                title: "原版微信",
                bundleIdentifier: "com.tencent.xinWeChat",
                appPath: OfficialWeChatApp.sourcePath,
                runningPids: runningSnapshot.pids(for: OfficialWeChatApp.sourcePath),
                isOriginal: true,
                isRunning: runningSnapshot.count(for: OfficialWeChatApp.sourcePath) > 0,
                includeDataSize: includeDataSizes
            ),
        ]
        for instance in instances.sorted(by: { $0.id < $1.id }) {
            items.append(item(
                id: instance.id,
                title: instance.name,
                bundleIdentifier: instance.bundleIdentifier,
                appPath: instance.appPath,
                runningPids: runningSnapshot.pids(for: instance.appPath),
                isOriginal: false,
                isRunning: runningSnapshot.count(for: instance.appPath) > 0,
                includeDataSize: includeDataSizes
            ))
        }
        return items
    }

    func clearContainer(for item: StorageItem) throws {
        guard !item.isOriginal else {
            return
        }
        guard !item.isRunning, !isRunning(appPath: item.appPath) else {
            throw NSError(domain: "StorageInspector", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "请先关闭该分身",
            ])
        }
        let containerURL = URL(fileURLWithPath: item.containerPath)
        let root = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .standardizedFileURL.path
        let target = containerURL.standardizedFileURL.path
        guard target.hasPrefix(root + "/"),
              item.bundleIdentifier.hasPrefix("com.tencent.xinWeChat.wxmulti.") else {
            throw NSError(domain: "StorageInspector", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "拒绝清除非托管容器",
            ])
        }
        guard fileManager.fileExists(atPath: target) else {
            return
        }
        let children = try fileManager.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for child in children where child.lastPathComponent != ".com.apple.containermanagerd.metadata.plist" {
            try fileManager.removeItem(at: child)
        }
    }

    private func isRunning(appPath: String?) -> Bool {
        guard let appPath else {
            return false
        }
        let executable = appPath + "/Contents/MacOS/WeChat"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do {
            try process.run()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .contains { line in
                line == executable || line.hasPrefix(executable + " ")
            }
    }

    private func item(
        id: String,
        title: String,
        bundleIdentifier: String,
        appPath: String?,
        runningPids: [Int32],
        isOriginal: Bool,
        isRunning: Bool,
        includeDataSize: Bool
    ) -> StorageItem {
        let containerURL = containerURL(bundleIdentifier: bundleIdentifier)
        let containerExists = fileManager.fileExists(atPath: containerURL.path)
        let dataBytes = includeDataSize ? directorySize(containerURL) : 0
        let activeAccountID = cachedActiveAccountID(containerURL: containerURL, pids: runningPids, force: includeDataSize)
        return StorageItem(
            id: id,
            title: title,
            bundleIdentifier: bundleIdentifier,
            appPath: appPath,
            containerPath: containerURL.path,
            containerExists: containerExists,
            dataBytes: dataBytes,
            isDataSizeKnown: includeDataSize,
            accounts: accountRecords(containerURL: containerURL, activeAccountID: activeAccountID),
            activeAccountID: activeAccountID,
            isOriginal: isOriginal,
            isRunning: isRunning
        )
    }

    private func containerURL(bundleIdentifier: String) -> URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    private func directorySize(_ url: URL) -> UInt64 {
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += UInt64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private func accountRecords(containerURL: URL, activeAccountID: String?) -> [StorageAccountRecord] {
        let documents = containerURL
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
        let roots = [
            documents
                .appendingPathComponent("app_data", isDirectory: true)
                .appendingPathComponent("login", isDirectory: true),
            documents.appendingPathComponent("xwechat_files", isDirectory: true),
        ]
        var recordsByID: [String: StorageAccountRecord] = [:]
        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for child in children {
                guard let id = accountID(from: child.lastPathComponent) else {
                    continue
                }
                let modifiedAt = (try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if let existing = recordsByID[id], existing.modifiedAt >= modifiedAt {
                    continue
                }
                recordsByID[id] = StorageAccountRecord(id: id, modifiedAt: modifiedAt)
            }
        }
        return recordsByID.values.sorted { lhs, rhs in
            if lhs.id == activeAccountID, rhs.id != activeAccountID {
                return true
            }
            if rhs.id == activeAccountID, lhs.id != activeAccountID {
                return false
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }

    private func activeAccountID(containerURL: URL, pids: [Int32]) -> String? {
        guard !pids.isEmpty else {
            return nil
        }
        let accountRoot = containerURL
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("xwechat_files", isDirectory: true)
            .standardizedFileURL
            .path
        for pid in pids {
            guard let output = lsofOutput(pid: pid) else {
                continue
            }
            for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.hasPrefix("n") else {
                    continue
                }
                let path = String(line.dropFirst())
                guard path.hasPrefix(accountRoot + "/") else {
                    continue
                }
                let relative = String(path.dropFirst(accountRoot.count + 1))
                guard let firstComponent = relative.split(separator: "/").first,
                      let id = accountID(from: String(firstComponent)) else {
                    continue
                }
                return id
            }
        }
        return nil
    }

    private func cachedActiveAccountID(containerURL: URL, pids: [Int32], force: Bool) -> String? {
        guard !pids.isEmpty else { return nil }
        let key = containerURL.path + ":" + pids.sorted().map(String.init).joined(separator: ",")
        accountCacheLock.lock()
        defer { accountCacheLock.unlock() }
        return accountCache.value(for: key, force: force) {
            activeAccountID(containerURL: containerURL, pids: pids)
        }
    }

    private func lsofOutput(pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-Fn", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func accountID(from name: String) -> String? {
        guard name.hasPrefix("wxid_") else {
            return nil
        }
        if let suffixRange = name.range(of: "_", options: .backwards),
           suffixRange.lowerBound > name.index(name.startIndex, offsetBy: 5) {
            return String(name[..<suffixRange.lowerBound])
        }
        return name
    }
}

struct AccountLookupCache {
    private struct Entry {
        var accountID: String?
        var expiresAt: TimeInterval
    }
    private var entries: [String: Entry] = [:]

    mutating func value(for key: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime,
                        force: Bool = false, lookup: () -> String?) -> String? {
        entries = entries.filter { $0.value.expiresAt > now }
        if !force, let entry = entries[key] { return entry.accountID }
        let result = lookup()
        entries[key] = Entry(accountID: result, expiresAt: now + 30)
        return result
    }
}

enum ByteFormatter {
    static func string(from bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
