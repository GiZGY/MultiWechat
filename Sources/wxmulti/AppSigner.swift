import Foundation

struct AppSigner {
    func sign(appURL: URL, entitlements: URL? = nil) throws {
        let runner = ProcessRunner()
        var arguments = ["--force", "--deep", "--sign", "-"]
        if let entitlements {
            arguments += ["--entitlements", entitlements.path]
        }
        arguments.append(appURL.path)
        try runner.run("/usr/bin/codesign", arguments)
        try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
    }
}
