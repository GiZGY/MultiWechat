import Foundation

struct EntitlementsBuilder {
    let runner: ProcessRunner

    func originalEntitlements(appURL: URL) throws -> [String: Any] {
        let result = try runner.run("/usr/bin/codesign", ["-d", "--entitlements", ":-", appURL.path], allowFailure: true)
        guard result.status == 0 else {
            try fail("无法读取原版微信 entitlements\n\(result.stderr)")
        }
        guard let data = result.stdout.data(using: .utf8), !data.isEmpty else {
            try fail("原版微信 entitlements 为空")
        }
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            try fail("无法解析原版微信 entitlements")
        }
        return dict
    }

    func writeEntitlements(
        sourceAppURL: URL,
        targetBundleID: String,
        mode: EntitlementsMode,
        to url: URL
    ) throws {
        switch mode {
        case .none:
            try PlistEditor.writeDictionary([:], to: url)
        case .preserve:
            let original = try originalEntitlements(appURL: sourceAppURL)
            try PlistEditor.writeDictionary(original, to: url)
        case .isolated:
            var entitlements = try originalEntitlements(appURL: sourceAppURL)
            let teamID = (entitlements["com.apple.developer.team-identifier"] as? String) ?? "5A4RE8SF68"
            let applicationID = "\(teamID).\(targetBundleID)"
            entitlements["com.apple.application-identifier"] = applicationID
            entitlements["com.apple.security.application-groups"] = [applicationID]
            entitlements["com.apple.developer.team-identifier"] = teamID
            try PlistEditor.writeDictionary(entitlements, to: url)
        }
    }
}
