import Foundation

enum PlistEditor {
    static func readDictionary(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            try fail("不是可识别的 plist 字典: \(url.path)")
        }
        return dict
    }

    static func writeDictionary(_ dict: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    static func stringValue(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }
}
