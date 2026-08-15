import Foundation

@main
struct WxMultiCLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as CommandError {
            fputs("错误: \(error.message)\n", stderr)
            exit(1)
        } catch {
            fputs("错误: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }
        let parser = ArgumentParser(Array(arguments.dropFirst()))
        let manager = WeChatInstanceManager()
        let binaryPatcher = WeChatBinaryPatcher()
        let hardManager = HardInstanceManager()
        switch command {
        case "doctor":
            try manager.doctor(sourcePath: parser.value(for: "--source"))
        case "list":
            try manager.list()
        case "create":
            guard let id = parser.positional.first else {
                try fail("create 需要实例 ID")
            }
            let mode = EntitlementsMode(rawValue: parser.value(for: "--entitlements") ?? "none")
            guard let mode else {
                try fail("--entitlements 仅支持 isolated、preserve、none")
            }
            try manager.create(
                id: id,
                name: parser.value(for: "--name"),
                explicitBundleID: parser.value(for: "--bundle-id"),
                appName: parser.value(for: "--app-name"),
                sourcePath: parser.value(for: "--source"),
                force: parser.hasFlag("--force"),
                mode: mode
            )
        case "start":
            guard let id = parser.positional.first else {
                try fail("start 需要实例 ID")
            }
            try manager.start(id: id)
        case "rebuild":
            guard let id = parser.positional.first else {
                try fail("rebuild 需要实例 ID")
            }
            try manager.rebuild(id: id)
        case "stop":
            guard let id = parser.positional.first else {
                try fail("stop 需要实例 ID")
            }
            try manager.stop(id: id)
        case "sync-runtime":
            guard let id = parser.positional.first else {
                try fail("sync-runtime 需要实例 ID")
            }
            try manager.syncRuntime(id: id)
        case "rename":
            guard let id = parser.positional.first else {
                try fail("rename 需要实例 ID")
            }
            guard let name = parser.value(for: "--name") else {
                try fail("rename 需要 --name 名称")
            }
            try manager.rename(id: id, name: name)
        case "remove":
            guard let id = parser.positional.first else {
                try fail("remove 需要实例 ID")
            }
            try manager.remove(id: id, deleteApp: parser.hasFlag("--delete-app"))
        case "patch-status":
            try binaryPatcher.status(sourcePath: parser.value(for: "--source"))
        case "patch-multi":
            try binaryPatcher.patchMultiInstance(
                sourcePath: parser.value(for: "--source"),
                force: parser.hasFlag("--force")
            )
        case "restore-multi":
            try binaryPatcher.restore(
                sourcePath: parser.value(for: "--source"),
                backupPath: parser.value(for: "--backup")
            )
        case "start-official":
            try binaryPatcher.launch(sourcePath: parser.value(for: "--source") ?? WeChatLocator.defaultAppPath)
        case "install-patched":
            try binaryPatcher.installPatchedClone(
                sourcePath: parser.value(for: "--source"),
                targetPath: parser.value(for: "--target"),
                force: parser.hasFlag("--force"),
                displayName: parser.value(for: "--name")
            )
        case "start-patched":
            try binaryPatcher.launch(
                sourcePath: parser.value(for: "--target"),
                count: try parser.positiveInt(for: "--count", defaultValue: 1)
            )
        case "stop-patched":
            try binaryPatcher.stopPatched(
                targetPath: parser.value(for: "--target"),
                mode: parser.hasFlag("--one") ? .one : .all
            )
        case "destroy-patched":
            try binaryPatcher.destroyPatchedClone(targetPath: parser.value(for: "--target"))
        case "patched-runtime-status":
            try binaryPatcher.patchedRuntimeStatus(targetPath: parser.value(for: "--target"))
        case "hard-list":
            try hardManager.list()
        case "hard-create":
            guard let id = parser.positional.first else {
                try fail("hard-create 需要槽位 ID")
            }
            try hardManager.create(
                id: id,
                name: parser.value(for: "--name"),
                sourcePath: parser.value(for: "--source"),
                targetPath: parser.value(for: "--target"),
                force: parser.hasFlag("--force")
            )
        case "hard-start":
            guard let id = parser.positional.first else {
                try fail("hard-start 需要槽位 ID")
            }
            try hardManager.start(id: id, count: try parser.positiveInt(for: "--count", defaultValue: 1))
        case "hard-stop":
            guard let id = parser.positional.first else {
                try fail("hard-stop 需要槽位 ID")
            }
            try hardManager.stop(id: id, mode: parser.hasFlag("--one") ? .one : .all)
        case "hard-rename":
            guard let id = parser.positional.first else {
                try fail("hard-rename 需要槽位 ID")
            }
            guard let name = parser.value(for: "--name") else {
                try fail("hard-rename 需要 --name 名称")
            }
            try hardManager.rename(id: id, name: name)
        case "hard-remove":
            guard let id = parser.positional.first else {
                try fail("hard-remove 需要槽位 ID")
            }
            try hardManager.remove(id: id, deleteApp: parser.hasFlag("--delete-app"))
        case "help", "-h", "--help":
            printHelp()
        default:
            try fail("未知命令: \(command)")
        }
    }

    static func printHelp() {
        print("""
        wxmulti - MultiWechat CLI

        用法:
          wxmulti doctor [--source /Applications/WeChat.app]
          wxmulti create <id> [--name 名称] [--bundle-id com.tencent.xinWeChat2] [--app-name WeChat2] [--source /Applications/WeChat.app] [--force] [--entitlements isolated|preserve|none]
          wxmulti start <id>
          wxmulti rebuild <id>
          wxmulti stop <id>
          wxmulti sync-runtime <id>
          wxmulti rename <id> --name 名称
          wxmulti list
          wxmulti remove <id> [--delete-app]

          wxmulti patch-status [--source /Applications/WeChat.app]
          wxmulti patch-multi [--source /Applications/WeChat.app] [--force]
          wxmulti restore-multi [--source /Applications/WeChat.app] [--backup /path/to/backup]
          wxmulti start-official [--source /Applications/WeChat.app]
          wxmulti install-patched [--source /Applications/WeChat.app] [--target /Applications/WeChatPatched.app] [--name 显示名] [--force]
          wxmulti start-patched [--target /Applications/WeChatPatched.app] [--count 1]
          wxmulti stop-patched [--target /Applications/WeChatPatched.app] [--one]
          wxmulti destroy-patched [--target /Applications/WeChatPatched.app]
          wxmulti patched-runtime-status [--target /Applications/WeChatPatched.app]

          wxmulti hard-create <id> [--name 显示名] [--source /Applications/WeChat.app] [--target /path/to/App.app] [--force]
          wxmulti hard-start <id> [--count 1]
          wxmulti hard-stop <id> [--one]
          wxmulti hard-rename <id> --name 显示名
          wxmulti hard-list
          wxmulti hard-remove <id> [--delete-app]
        """)
    }
}

struct ArgumentParser {
    var positional: [String] = []
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            if arg.hasPrefix("--") {
                if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                    values[arg] = arguments[index + 1]
                    index += 2
                } else {
                    flags.insert(arg)
                    index += 1
                }
            } else {
                positional.append(arg)
                index += 1
            }
        }
    }

    func value(for key: String) -> String? {
        values[key]
    }

    func hasFlag(_ key: String) -> Bool {
        flags.contains(key)
    }

    func positiveInt(for key: String, defaultValue: Int) throws -> Int {
        guard let raw = value(for: key) else {
            return defaultValue
        }
        guard let value = Int(raw), value > 0 else {
            try fail("\(key) 必须是大于 0 的整数")
        }
        return value
    }
}
