import Foundation

struct WeChatPatchEntry: Equatable {
    var architecture: String
    var relativePath: String
    var virtualAddress: UInt64
    var expectedBytes: [[UInt8]]
    var bytes: [UInt8]

    init(
        architecture: String,
        virtualAddress: UInt64,
        bytes: [UInt8],
        expectedBytes: [[UInt8]] = [],
        relativePath: String = "Contents/MacOS/WeChat"
    ) {
        self.architecture = architecture
        self.relativePath = relativePath
        self.virtualAddress = virtualAddress
        self.expectedBytes = expectedBytes
        self.bytes = bytes
    }
}

struct WeChatBinaryPatcher {
    private static let patchBytes = [UInt8](hex: "20008052C0035FD6")
    static let defaultPatchedAppPath = "/Applications/WeChatPatched.app"

    private static let supportedPatches: [String: [WeChatPatchEntry]] = [
        "31927": [
            WeChatPatchEntry(architecture: "arm64", virtualAddress: 0x1001e1c10, bytes: patchBytes),
        ],
        "31960": [
            WeChatPatchEntry(architecture: "arm64", virtualAddress: 0x1001e4a38, bytes: patchBytes),
        ],
        "32281": [
            WeChatPatchEntry(architecture: "arm64", virtualAddress: 0x1001e1a74, bytes: patchBytes),
        ],
        "32288": [
            WeChatPatchEntry(architecture: "arm64", virtualAddress: 0x1001e1a74, bytes: patchBytes),
        ],
        "34371": [
            WeChatPatchEntry(architecture: "arm64", virtualAddress: 0x1001b82c4, bytes: patchBytes),
        ],
        "268624": [
            WeChatPatchEntry(
                architecture: "arm64",
                virtualAddress: 0x10001e664,
                bytes: patchBytes,
                expectedBytes: [[UInt8](hex: "FF8306D1F65717A9")]
            ),
            WeChatPatchEntry(
                architecture: "arm64",
                virtualAddress: 0x10002450c,
                bytes: [UInt8](hex: "13008052"),
                expectedBytes: [[UInt8](hex: "13008012")]
            ),
            WeChatPatchEntry(
                architecture: "arm64",
                virtualAddress: 0x100025bd0,
                bytes: [UInt8](hex: "13008052"),
                expectedBytes: [[UInt8](hex: "13008012")]
            ),
            WeChatPatchEntry(
                architecture: "arm64",
                virtualAddress: 0x100025d90,
                bytes: [UInt8](hex: "F3031FAA"),
                expectedBytes: [[UInt8](hex: "F30300AA")]
            ),
            WeChatPatchEntry(
                architecture: "arm64",
                virtualAddress: 0x100025d94,
                bytes: [UInt8](hex: "B4000014"),
                expectedBytes: [[UInt8](hex: "40190034")]
            ),
            WeChatPatchEntry(
                architecture: "arm64",
                virtualAddress: 0x1ec658,
                bytes: [UInt8](hex: "1F2003D5"),
                expectedBytes: [[UInt8](hex: "E0000037")],
                relativePath: "Contents/Resources/wechat.dylib"
            ),
        ],
    ]

    let locator: WeChatLocator
    let runner: ProcessRunner
    let inspector: ProcessInspector

    init(locator: WeChatLocator = WeChatLocator(), runner: ProcessRunner = ProcessRunner()) {
        self.locator = locator
        self.runner = runner
        self.inspector = ProcessInspector(runner: runner)
    }

    func status(sourcePath: String?) throws {
        let source = try locator.resolve(sourcePath: sourcePath)
        let version = source.bundleVersion ?? "-"
        let supported = Self.supportedPatches[version] != nil
        print("微信路径: \(source.appURL.path)")
        print("版本: \(source.shortVersion ?? "-") (\(version))")
        print("多开补丁: \(supported ? "支持" : "不支持")")
        print("已知版本: \(Self.supportedPatches.keys.sorted().joined(separator: ", "))")
        let state = try currentPatchState(source: source)
        print("当前状态: \(state.description)")
    }

    func patchMultiInstance(sourcePath: String?, force: Bool) throws {
        let source = try locator.resolve(sourcePath: sourcePath)
        let version = source.bundleVersion ?? ""
        guard let entries = Self.supportedPatches[version] else {
            try fail("当前微信构建号 \(version.isEmpty ? "-" : version) 不在补丁支持列表内，拒绝盲写")
        }
        let running = try inspector.runningProcesses(executablePath: source.executableURL.path)
        if !running.isEmpty, !force {
            try fail("原版微信正在运行，请先完全退出后再执行。需要强制操作可加 --force")
        }

        let state = try currentPatchState(source: source)
        if state == .patched {
            print("多开补丁已存在，无需重复写入")
            return
        }

        let backupURLs = try backupPatchTargets(source: source, entries: entries, version: version)
        for backupURL in backupURLs {
            print("已备份原始文件: \(backupURL.path)")
        }

        var editors: [String: MachOEditor] = [:]
        for entry in entries {
            let fileURL = patchTargetURL(source: source, entry: entry)
            let key = fileURL.path
            let editor = try editors[key] ?? MachOEditor(fileURL: fileURL)
            editors[key] = editor
            try editor.patch(
                virtualAddress: entry.virtualAddress,
                bytes: entry.bytes,
                expectedBytes: entry.expectedBytes
            )
            print("已写入 \(entry.architecture) \(entry.relativePath) VA 0x\(String(entry.virtualAddress, radix: 16))")
        }
        try resign(appURL: source.appURL)
        print("多开补丁已启用。现在可用 open -n 启动第二个原版微信实例")
    }

    func restore(sourcePath: String?, backupPath: String?) throws {
        let source = try locator.resolve(sourcePath: sourcePath)
        let backupURL: URL
        if let backupPath, !backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            backupURL = URL(fileURLWithPath: backupPath)
        } else {
            backupURL = try latestBackupURL(for: source)
        }
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            try fail("未找到备份: \(backupURL.path)")
        }
        let running = try inspector.runningProcesses(executablePath: source.executableURL.path)
        if !running.isEmpty {
            try fail("原版微信正在运行，请先完全退出后再还原")
        }
        try FileManager.default.copyReplacingItem(at: backupURL, to: source.executableURL)
        try runner.run("/bin/chmod", ["755", source.executableURL.path])
        try resign(appURL: source.appURL)
        print("已还原微信二进制: \(backupURL.path)")
    }

    func installPatchedClone(sourcePath: String?, targetPath: String?, force: Bool, displayName: String? = nil) throws {
        let source = try locator.resolve(sourcePath: sourcePath)
        let targetURL = URL(fileURLWithPath: targetPath ?? Self.defaultPatchedAppPath)
        let targetPath = targetURL.standardizedFileURL.path
        let sourcePath = source.appURL.standardizedFileURL.path
        guard targetPath != sourcePath, !targetPath.hasPrefix(sourcePath + "/") else {
            try fail("补丁副本目标不能等于或位于原版微信 App 内")
        }
        if FileManager.default.fileExists(atPath: targetPath) {
            if !force {
                try fail("目标 App 已存在: \(targetPath)。需要重建时请加 --force")
            }
            let running = try inspector.runningProcesses(matching: targetPath + "/")
            if !running.isEmpty {
                try fail("补丁副本正在运行，请先 stop-patched 后再重建")
            }
            try runner.run("/bin/chmod", ["-R", "u+rwX", targetPath], allowFailure: true)
            try FileManager.default.removeItem(at: targetURL)
        }
        try runner.run("/usr/bin/ditto", [source.appURL.path, targetPath])
        try runner.run("/usr/bin/xattr", ["-cr", targetPath], allowFailure: true)
        if let displayName {
            try updateDisplayName(appURL: targetURL, displayName: displayName)
        }
        try patchMultiInstance(sourcePath: targetPath, force: true)
        print("硬多开 App 已创建: \(targetPath)")
    }

    func launch(sourcePath: String?, count: Int = 1) throws {
        guard count > 0 else {
            try fail("启动数量必须大于 0")
        }
        let source = try locator.resolve(sourcePath: sourcePath ?? Self.defaultPatchedAppPath)
        for index in 0..<count {
            try runner.run("/usr/bin/open", ["-n", "-a", source.appURL.path])
            if index + 1 < count {
                Thread.sleep(forTimeInterval: 0.8)
            }
        }
        print("已发送启动命令: \(source.appURL.path) x\(count)")
    }

    func patchedRuntimeStatus(targetPath: String?) throws {
        let appURL = URL(fileURLWithPath: targetPath ?? Self.defaultPatchedAppPath).standardizedFileURL
        let processes = try runningPatchedMainProcesses(appURL: appURL)
        print("硬多开 App: \(appURL.path)")
        print("运行分身数: \(processes.count)")
        if !processes.isEmpty {
            print("PID: \(processes.map { String($0.pid) }.joined(separator: ", "))")
        }
    }

    func stopPatched(targetPath: String?, mode: PatchedStopMode = .all) throws {
        let appURL = URL(fileURLWithPath: targetPath ?? Self.defaultPatchedAppPath).standardizedFileURL
        let originalPath = (try? locator.resolve(sourcePath: nil).appURL.standardizedFileURL.path) ?? WeChatLocator.defaultAppPath
        guard appURL.path != originalPath else {
            try fail("拒绝关闭原版微信")
        }
        let processes: [RunningProcess]
        switch mode {
        case .all:
            processes = try runningPatchedMainProcesses(appURL: appURL)
        case .one:
            let mainProcesses = try runningPatchedMainProcesses(appURL: appURL)
            processes = mainProcesses.max(by: { $0.pid < $1.pid }).map { [$0] } ?? []
        }
        guard !processes.isEmpty else {
            print("硬多开未运行: \(appURL.path)")
            return
        }
        for process in processes {
            try runner.run("/bin/kill", ["-TERM", "\(process.pid)"], allowFailure: true)
        }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let remaining = processes.filter { inspector.isRunning($0.pid) }
            if remaining.isEmpty {
                switch mode {
                case .all:
                    print("硬多开已关闭: \(appURL.path)")
                case .one:
                    print("已关闭一个硬多开分身: \(appURL.path)")
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        for process in processes {
            try runner.run("/bin/kill", ["-KILL", "\(process.pid)"], allowFailure: true)
        }
        switch mode {
        case .all:
            print("硬多开已强制关闭: \(appURL.path)")
        case .one:
            print("已强制关闭一个硬多开分身: \(appURL.path)")
        }
    }

    func destroyPatchedClone(targetPath: String?) throws {
        let appURL = URL(fileURLWithPath: targetPath ?? Self.defaultPatchedAppPath).standardizedFileURL
        let originalPath = (try? locator.resolve(sourcePath: nil).appURL.standardizedFileURL.path) ?? WeChatLocator.defaultAppPath
        guard appURL.path != originalPath else {
            try fail("拒绝销毁原版微信")
        }
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            print("硬多开 App 不存在: \(appURL.path)")
            return
        }
        try stopPatched(targetPath: appURL.path)
        try runner.run("/bin/chmod", ["-R", "u+rwX", appURL.path], allowFailure: true)
        try FileManager.default.removeItem(at: appURL)
        print("硬多开 App 已销毁: \(appURL.path)")
    }

    private func runningPatchedMainProcesses(appURL: URL) throws -> [RunningProcess] {
        let executablePath = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("WeChat")
            .path
        return try inspector.runningProcesses(executablePath: executablePath)
    }

    private func currentPatchState(source: WeChatAppInfo) throws -> PatchState {
        guard let version = source.bundleVersion, let entries = Self.supportedPatches[version] else {
            return .unsupported
        }
        var editors: [String: MachOEditor] = [:]
        let allPatched = try entries.allSatisfy { entry in
            let fileURL = patchTargetURL(source: source, entry: entry)
            let key = fileURL.path
            let editor = try editors[key] ?? MachOEditor(fileURL: fileURL)
            editors[key] = editor
            return try editor.bytes(atVirtualAddress: entry.virtualAddress, count: entry.bytes.count) == entry.bytes
        }
        return allPatched ? .patched : .unpatched
    }

    private func patchTargetURL(source: WeChatAppInfo, entry: WeChatPatchEntry) -> URL {
        if entry.relativePath == "Contents/MacOS/WeChat" {
            return source.executableURL
        }
        return source.appURL.appendingPathComponent(entry.relativePath)
    }

    private func backupPatchTargets(source: WeChatAppInfo, entries: [WeChatPatchEntry], version: String) throws -> [URL] {
        var seen = Set<String>()
        var backups: [URL] = []
        for entry in entries {
            let fileURL = patchTargetURL(source: source, entry: entry)
            guard !seen.contains(fileURL.path) else {
                continue
            }
            seen.insert(fileURL.path)
            backups.append(try backupFile(fileURL, version: version))
        }
        return backups
    }

    private func backupBinary(source: WeChatAppInfo, version: String) throws -> URL {
        try backupFile(source.executableURL, version: version)
    }

    private func backupFile(_ fileURL: URL, version: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = formatter.string(from: Date())
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).wxmulti-backup-\(version)-\(suffix)")
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        return backupURL
    }

    private func latestBackupURL(for source: WeChatAppInfo) throws -> URL {
        let directory = source.executableURL.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("WeChat.wxmulti-backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let latest = backups.first else {
            try fail("未找到 wxmulti 备份")
        }
        return latest
    }

    private func resign(appURL: URL) throws {
        try AppSigner().sign(appURL: appURL)
        try runner.run("/usr/bin/xattr", ["-cr", appURL.path], allowFailure: true)
    }

    private func updateDisplayName(appURL: URL, displayName: String) throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let infoURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        var plist = try PlistEditor.readDictionary(infoURL)
        plist["CFBundleName"] = trimmed
        plist["CFBundleDisplayName"] = trimmed
        try PlistEditor.writeDictionary(plist, to: infoURL)
    }
}

enum PatchedStopMode {
    case all
    case one
}

private enum PatchState: Equatable {
    case unsupported
    case patched
    case unpatched

    var description: String {
        switch self {
        case .unsupported:
            return "当前版本不支持"
        case .patched:
            return "已启用"
        case .unpatched:
            return "未启用"
        }
    }
}

private struct MachOEditor {
    private let fileURL: URL
    private let data: Data
    private let slice: MachOSlice

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.data = try Data(contentsOf: fileURL)
        self.slice = try MachOParser(data: data).arm64Slice()
    }

    func bytes(atVirtualAddress virtualAddress: UInt64, count: Int) throws -> [UInt8] {
        let offset = try fileOffset(forVirtualAddress: virtualAddress, byteCount: count)
        guard offset + count <= data.count else {
            try fail("补丁地址越界: 0x\(String(virtualAddress, radix: 16))")
        }
        return Array(data[offset..<(offset + count)])
    }

    func patch(virtualAddress: UInt64, bytes: [UInt8], expectedBytes: [[UInt8]] = []) throws {
        let offset = try fileOffset(forVirtualAddress: virtualAddress, byteCount: bytes.count)
        let original = try self.bytes(atVirtualAddress: virtualAddress, count: bytes.count)
        if original == bytes {
            return
        }
        if !expectedBytes.isEmpty, !expectedBytes.contains(original) {
            let address = "0x\(String(virtualAddress, radix: 16))"
            let expected = expectedBytes.map(\.hexString).joined(separator: " / ")
            try fail("补丁地址 \(address) 当前字节 \(original.hexString) 不匹配，期望 \(expected)")
        }
        let handle = try FileHandle(forUpdating: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: Data(bytes))
    }

    private func fileOffset(forVirtualAddress virtualAddress: UInt64, byteCount: Int) throws -> Int {
        for segment in slice.segments {
            guard virtualAddress >= segment.vmaddr else {
                continue
            }
            let delta = virtualAddress - segment.vmaddr
            guard delta + UInt64(byteCount) <= segment.filesize else {
                continue
            }
            let fileOffset = slice.offset + Int(segment.fileoff + delta)
            guard fileOffset >= 0, fileOffset + byteCount <= data.count else {
                try fail("补丁文件偏移越界: 0x\(String(virtualAddress, radix: 16))")
            }
            return fileOffset
        }
        try fail("无法映射 Mach-O 虚拟地址: 0x\(String(virtualAddress, radix: 16))")
    }
}

private struct MachOSlice {
    var offset: Int
    var segments: [MachOSegment]
}

private struct MachOSegment {
    var vmaddr: UInt64
    var filesize: UInt64
    var fileoff: UInt64
}

private struct MachOParser {
    private static let cpuTypeArm64: UInt32 = 0x0100000c
    private static let fatMagic: UInt32 = 0xcafebabe
    private static let fatMagic64: UInt32 = 0xcafebabf
    private static let machHeader64Magic: UInt32 = 0xfeedfacf
    private static let lcSegment64: UInt32 = 0x19

    let data: Data

    func arm64Slice() throws -> MachOSlice {
        guard data.count >= 4 else {
            try fail("Mach-O 文件过小")
        }
        let magicBE = try data.uint32BE(at: 0)
        if magicBE == Self.fatMagic || magicBE == Self.fatMagic64 {
            return try parseFat(is64: magicBE == Self.fatMagic64)
        }
        let magicLE = try data.uint32LE(at: 0)
        guard magicLE == Self.machHeader64Magic else {
            try fail("不支持的 Mach-O 格式")
        }
        return try parseThinMachO(at: 0)
    }

    private func parseFat(is64: Bool) throws -> MachOSlice {
        let count = Int(try data.uint32BE(at: 4))
        let archSize = is64 ? 32 : 20
        for index in 0..<count {
            let base = 8 + index * archSize
            let cpuType = try data.uint32BE(at: base)
            guard cpuType == Self.cpuTypeArm64 else {
                continue
            }
            let offset: UInt64
            if is64 {
                offset = try data.uint64BE(at: base + 8)
            } else {
                offset = UInt64(try data.uint32BE(at: base + 8))
            }
            guard offset <= UInt64(Int.max) else {
                try fail("Mach-O slice 偏移过大")
            }
            return try parseThinMachO(at: Int(offset))
        }
        try fail("未找到 arm64 Mach-O slice")
    }

    private func parseThinMachO(at sliceOffset: Int) throws -> MachOSlice {
        guard try data.uint32LE(at: sliceOffset) == Self.machHeader64Magic else {
            try fail("arm64 slice 不是 64-bit Mach-O")
        }
        let commandCount = Int(try data.uint32LE(at: sliceOffset + 16))
        var commandOffset = sliceOffset + 32
        var segments: [MachOSegment] = []
        for _ in 0..<commandCount {
            let command = try data.uint32LE(at: commandOffset)
            let commandSize = Int(try data.uint32LE(at: commandOffset + 4))
            guard commandSize >= 8 else {
                try fail("Mach-O load command 异常")
            }
            if command == Self.lcSegment64 {
                segments.append(MachOSegment(
                    vmaddr: try data.uint64LE(at: commandOffset + 24),
                    filesize: try data.uint64LE(at: commandOffset + 48),
                    fileoff: try data.uint64LE(at: commandOffset + 40)
                ))
            }
            commandOffset += commandSize
            guard commandOffset <= data.count else {
                try fail("Mach-O load command 越界")
            }
        }
        guard !segments.isEmpty else {
            try fail("未找到 Mach-O segment")
        }
        return MachOSlice(offset: sliceOffset, segments: segments)
    }
}

private extension Data {
    func uint32LE(at offset: Int) throws -> UInt32 {
        try readInteger(at: offset, byteCount: 4, endian: .little)
    }

    func uint32BE(at offset: Int) throws -> UInt32 {
        try readInteger(at: offset, byteCount: 4, endian: .big)
    }

    func uint64LE(at offset: Int) throws -> UInt64 {
        try readInteger(at: offset, byteCount: 8, endian: .little)
    }

    func uint64BE(at offset: Int) throws -> UInt64 {
        try readInteger(at: offset, byteCount: 8, endian: .big)
    }

    private enum Endian {
        case little
        case big
    }

    private func readInteger<T: FixedWidthInteger>(at offset: Int, byteCount: Int, endian: Endian) throws -> T {
        guard offset >= 0, offset + byteCount <= count else {
            try fail("读取 Mach-O 数据越界")
        }
        var value: T = 0
        for index in 0..<byteCount {
            let byte = T(self[offset + index])
            switch endian {
            case .little:
                value |= byte << T(index * 8)
            case .big:
                value = (value << 8) | byte
            }
        }
        return value
    }
}

private extension Array where Element == UInt8 {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        self = bytes
    }

    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

private extension FileManager {
    func copyReplacingItem(at sourceURL: URL, to targetURL: URL) throws {
        if fileExists(atPath: targetURL.path) {
            try removeItem(at: targetURL)
        }
        try copyItem(at: sourceURL, to: targetURL)
    }
}
