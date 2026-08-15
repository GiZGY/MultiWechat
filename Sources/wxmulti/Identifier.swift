import Foundation

enum Identifier {
    static func normalizedInstanceID(_ raw: String) throws -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var output = ""
        var previousWasDash = false
        for scalar in lower.unicodeScalars {
            let isAllowed =
                CharacterSet.lowercaseLetters.contains(scalar) ||
                CharacterSet.decimalDigits.contains(scalar)
            if isAllowed {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                output.append("-")
                previousWasDash = true
            }
        }
        output = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if output.isEmpty {
            try fail("实例 ID 不能为空，建议使用 work、life 这类英文短名")
        }
        if output.count > 32 {
            try fail("实例 ID 不能超过 32 个字符")
        }
        return output
    }

    static func bundleIdentifier(base: String, instanceID: String) -> String {
        "\(base).wxmulti.\(instanceID.replacingOccurrences(of: "-", with: "."))"
    }

    static func explicitBundleIdentifier(_ raw: String?) throws -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            try fail("Bundle ID 只能包含字母、数字、点和短横线")
        }
        guard trimmed.contains(".") else {
            try fail("Bundle ID 至少应包含一个点，例如 com.tencent.xinWeChat2")
        }
        return trimmed
    }

    static func displayName(defaultID: String, explicitName: String?) -> String {
        let trimmed = explicitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "微信-\(defaultID)" : trimmed
    }

    static func appBundleName(defaultID: String, explicitName: String?) throws -> String {
        let trimmed = explicitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? "WeChat-\(defaultID)" : trimmed
        let forbidden = CharacterSet(charactersIn: "/:")
        guard name.rangeOfCharacter(from: forbidden) == nil else {
            try fail("App 名称不能包含 / 或 :")
        }
        return name.hasSuffix(".app") ? name : "\(name).app"
    }
}
