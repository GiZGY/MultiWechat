import Foundation

enum HelperExecutableRecovery {
    static func isMachO(_ url: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 4) else { return false }
        return [[0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe],
                [0xfe, 0xed, 0xfa, 0xcf], [0xcf, 0xfa, 0xed, 0xfe],
                [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
                [0xca, 0xfe, 0xba, 0xbf], [0xbf, 0xba, 0xfe, 0xca]]
            .contains(Array(header).map(Int.init))
    }

    @discardableResult
    static func restoreIfNeeded(at destination: URL, candidates: [URL]) throws -> Bool {
        guard !isMachO(destination) else { return false }
        guard let source = candidates.first(where: isMachO) else {
            try fail("辅助组件缺少真实可执行文件，请更新原版微信后重建分身")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: source, to: temporary)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
        return true
    }
}
