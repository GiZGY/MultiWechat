import Foundation

struct InstanceStoreRepository {
    let storeURL: URL

    func load() throws -> InstanceStore {
        let manager = FileManager.default
        guard manager.fileExists(atPath: storeURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: storeURL)
        if data.isEmpty {
            return .empty
        }
        return try JSONDecoder().decode(InstanceStore.self, from: data)
    }

    func save(_ store: InstanceStore) throws {
        let manager = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        try manager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        let tmpURL = dir.appendingPathComponent(".instances.\(UUID().uuidString).tmp")
        try data.write(to: tmpURL, options: .atomic)
        if manager.fileExists(atPath: storeURL.path) {
            _ = try manager.replaceItemAt(storeURL, withItemAt: tmpURL)
        } else {
            try manager.moveItem(at: tmpURL, to: storeURL)
        }
    }
}

struct HardInstanceStoreRepository {
    let storeURL: URL

    func load() throws -> HardInstanceStore {
        let manager = FileManager.default
        guard manager.fileExists(atPath: storeURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: storeURL)
        if data.isEmpty {
            return .empty
        }
        return try JSONDecoder().decode(HardInstanceStore.self, from: data)
    }

    func save(_ store: HardInstanceStore) throws {
        let manager = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        try manager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        let tmpURL = dir.appendingPathComponent(".hard-instances.\(UUID().uuidString).tmp")
        try data.write(to: tmpURL, options: .atomic)
        if manager.fileExists(atPath: storeURL.path) {
            _ = try manager.replaceItemAt(storeURL, withItemAt: tmpURL)
        } else {
            try manager.moveItem(at: tmpURL, to: storeURL)
        }
    }
}
