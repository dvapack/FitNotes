import SwiftData
import Foundation

enum ModelContainerFactoryError: LocalizedError {
    case sharedStoreLoadFailed(storeURL: URL, underlyingErrorDescription: String)

    var failureReason: String {
        switch self {
        case let .sharedStoreLoadFailed(_, underlyingErrorDescription):
            if underlyingErrorDescription.localizedCaseInsensitiveContains("unknown coordinator model version") {
                return "This store was created before FitNotes started versioning its SwiftData schema, so iOS can't perform a staged migration for it."
            }

            return "FitNotes couldn't open the current SwiftData store with the active schema."
        }
    }

    var recoverySuggestion: String {
        switch self {
        case let .sharedStoreLoadFailed(_, underlyingErrorDescription):
            if underlyingErrorDescription.localizedCaseInsensitiveContains("unknown coordinator model version") {
                return "Your existing files have been preserved. If you still need that data, keep a copy of the store files before using Reset Local Data."
            }

            return "Try reopening the store first. If it still won't load and you don't need the current on-device data, you can reset local storage and start fresh."
        }
    }

    var errorDescription: String? {
        switch self {
        case let .sharedStoreLoadFailed(storeURL, underlyingErrorDescription):
            return """
            FitNotes couldn't open its local data store at \(storeURL.path).
            \(underlyingErrorDescription)
            """
        }
    }
}

enum ModelContainerFactory {
    static let schema = Schema(versionedSchema: AppSchemaV1.self)

    static func makeSharedContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(url: try defaultStoreURL())
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            throw ModelContainerFactoryError.sharedStoreLoadFailed(
                storeURL: try defaultStoreURL(),
                underlyingErrorDescription: String(describing: error)
            )
        }
    }

    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create in-memory model container: \(error)")
        }
    }

    static func defaultStoreURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appendingPathComponent("default.store")
    }

    static func resetStoreFiles(at storeURL: URL) throws {
        let sidecarExtensions = ["", "-shm", "-wal"]

        for suffix in sidecarExtensions {
            let candidateURL = suffix.isEmpty ? storeURL : URL(fileURLWithPath: storeURL.path + suffix)
            if FileManager.default.fileExists(atPath: candidateURL.path()) {
                try FileManager.default.removeItem(at: candidateURL)
            }
        }
    }
}
