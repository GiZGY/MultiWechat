import Foundation

struct WeChatLocator {
    static let defaultAppPath = "/Applications/WeChat.app"

    func resolve(sourcePath: String?) throws -> WeChatAppInfo {
        let rawPath = sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appPath = (rawPath?.isEmpty == false ? rawPath! : Self.defaultAppPath)
        let appURL = URL(fileURLWithPath: appPath)
        let infoURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoURL.path) else {
            try fail("未找到微信 App: \(appPath)")
        }
        let plist = try PlistEditor.readDictionary(infoURL)
        guard let bundleID = PlistEditor.stringValue(plist, "CFBundleIdentifier"), !bundleID.isEmpty else {
            try fail("无法读取微信 Bundle ID")
        }
        guard let executable = PlistEditor.stringValue(plist, "CFBundleExecutable"), !executable.isEmpty else {
            try fail("无法读取微信可执行文件名")
        }
        return WeChatAppInfo(
            appURL: appURL,
            bundleIdentifier: bundleID,
            executableName: executable,
            shortVersion: PlistEditor.stringValue(plist, "CFBundleShortVersionString"),
            bundleVersion: PlistEditor.stringValue(plist, "CFBundleVersion")
        )
    }
}
