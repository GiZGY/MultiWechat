import Foundation

struct WxMultiPaths {
    let home: URL
    let appSupportDir: URL
    let appRootDir: URL
    let hardAppRootDir: URL
    let storeURL: URL
    let hardStoreURL: URL
    let entitlementsDir: URL
    let staleAppDir: URL

    static func defaults() -> WxMultiPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupportDir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("WxMulti", isDirectory: true)
        let appRootDir = home
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("WxMulti", isDirectory: true)
        return WxMultiPaths(
            home: home,
            appSupportDir: appSupportDir,
            appRootDir: appRootDir,
            hardAppRootDir: appRootDir.appendingPathComponent("Hard", isDirectory: true),
            storeURL: appSupportDir.appendingPathComponent("instances.json"),
            hardStoreURL: appSupportDir.appendingPathComponent("hard-instances.json"),
            entitlementsDir: appSupportDir.appendingPathComponent("entitlements", isDirectory: true),
            staleAppDir: appRootDir.appendingPathComponent(".stale", isDirectory: true)
        )
    }

    func ensureBaseDirectories() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try manager.createDirectory(at: appRootDir, withIntermediateDirectories: true)
        try manager.createDirectory(at: hardAppRootDir, withIntermediateDirectories: true)
        try manager.createDirectory(at: entitlementsDir, withIntermediateDirectories: true)
        try manager.createDirectory(at: staleAppDir, withIntermediateDirectories: true)
    }
}
