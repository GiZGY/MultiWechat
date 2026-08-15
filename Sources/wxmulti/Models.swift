import Foundation

enum EntitlementsMode: String, Codable {
    case isolated
    case preserve
    case none
}

struct InstanceProfile: Codable, Equatable {
    var id: String
    var name: String
    var bundleIdentifier: String
    var appPath: String
    var sourceAppPath: String
    var sourceShortVersion: String?
    var sourceBundleVersion: String?
    var sourceFingerprint: String?
    var sourceRuntimeFingerprint: String?
    var entitlementsMode: EntitlementsMode
    var createdAt: Int64
    var lastLaunchedAt: Int64?
    var lastPid: Int32?
}

struct InstanceStore: Codable, Equatable {
    var instances: [InstanceProfile]

    static let empty = InstanceStore(instances: [])
}

struct HardInstanceProfile: Codable, Equatable {
    var id: String
    var name: String
    var appPath: String
    var sourceAppPath: String
    var sourceShortVersion: String?
    var sourceBundleVersion: String?
    var createdAt: Int64
    var updatedAt: Int64
    var lastLaunchedAt: Int64?
}

struct HardInstanceStore: Codable, Equatable {
    var instances: [HardInstanceProfile]

    static let empty = HardInstanceStore(instances: [])
}

struct WeChatAppInfo: Equatable {
    var appURL: URL
    var bundleIdentifier: String
    var executableName: String
    var shortVersion: String?
    var bundleVersion: String?

    var executableURL: URL {
        appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
    }
}

struct RunningProcess: Equatable {
    var pid: Int32
    var command: String
}

struct LaunchProfile: Equatable {
    var clientVersion: String?
    var unifiedPCMacWechat: String?
    var runtimeBundleIdentifier: String?
}
