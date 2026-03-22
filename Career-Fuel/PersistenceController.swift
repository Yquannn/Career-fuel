import Foundation
import SwiftData

@Model
final class PersistedSnapshotRecord {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date

    init(key: String, payload: Data, updatedAt: Date) {
        self.key = key
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@MainActor
final class PersistenceController {
    let container: ModelContainer?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults = UserDefaults.standard

    init(inMemory: Bool = false) {
        let schema = Schema([PersistedSnapshotRecord.self])
        let primaryConfiguration = Self.makeConfiguration(schema: schema, inMemory: inMemory)

        do {
            container = try Self.makeContainer(schema: schema, configuration: primaryConfiguration)
        } catch {
            if inMemory {
                container = nil
                return
            }

            Self.destroyStoreFiles()

            do {
                container = try Self.makeContainer(schema: schema, configuration: primaryConfiguration)
            } catch {
                let inMemoryConfiguration = Self.makeConfiguration(schema: schema, inMemory: true)

                do {
                    container = try Self.makeContainer(schema: schema, configuration: inMemoryConfiguration)
                } catch {
                    container = nil
                }
            }
        }
    }

    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        if let record = record(forKey: key), let decoded = try? decoder.decode(type, from: record.payload) {
            return decoded
        }

        guard
            let data = defaults.data(forKey: defaultsKey(for: key)),
            let wrapper = try? decoder.decode(FallbackRecord.self, from: data)
        else {
            return nil
        }

        return try? decoder.decode(type, from: wrapper.payload)
    }

    func save<T: Encodable>(_ value: T, forKey key: String, updatedAt: Date = Date()) {
        guard let data = try? encoder.encode(value) else { return }
        let fallbackRecord = FallbackRecord(payload: data, updatedAt: updatedAt)

        if let fallbackData = try? encoder.encode(fallbackRecord) {
            defaults.set(fallbackData, forKey: defaultsKey(for: key))
        }

        guard let container else { return }

        if let existing = record(forKey: key) {
            existing.payload = data
            existing.updatedAt = updatedAt
        } else {
            let record = PersistedSnapshotRecord(key: key, payload: data, updatedAt: updatedAt)
            container.mainContext.insert(record)
        }

        try? container.mainContext.save()
    }

    func lastUpdatedAt(forKey key: String) -> Date? {
        if let updatedAt = record(forKey: key)?.updatedAt {
            return updatedAt
        }

        guard
            let data = defaults.data(forKey: defaultsKey(for: key)),
            let wrapper = try? decoder.decode(FallbackRecord.self, from: data)
        else {
            return nil
        }

        return wrapper.updatedAt
    }

    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: defaultsKey(for: key))

        guard let container, let existing = record(forKey: key) else { return }
        container.mainContext.delete(existing)
        try? container.mainContext.save()
    }

    private func record(forKey key: String) -> PersistedSnapshotRecord? {
        guard let container else { return nil }

        let descriptor = FetchDescriptor<PersistedSnapshotRecord>(
            predicate: #Predicate<PersistedSnapshotRecord> { record in
                record.key == key
            }
        )

        return try? container.mainContext.fetch(descriptor).first
    }

    private static func makeContainer(
        schema: Schema,
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: configuration)
    }

    private static func makeConfiguration(
        schema: Schema,
        inMemory: Bool
    ) -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }

        return ModelConfiguration(schema: schema, url: storeURL)
    }

    private static var storeURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let folderURL = directory.appendingPathComponent("CareerFuel", isDirectory: true)

        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        return folderURL.appendingPathComponent("CareerFuel.store")
    }

    private static func destroyStoreFiles() {
        let fileManager = FileManager.default
        let url = storeURL
        let sidecarURLs = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal"),
        ]

        for fileURL in sidecarURLs where fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func defaultsKey(for key: String) -> String {
        "careerfuel.persistence.\(key)"
    }
}

private extension PersistenceController {
    struct FallbackRecord: Codable {
        let payload: Data
        let updatedAt: Date
    }
}
