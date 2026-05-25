import SwiftData
import Foundation
import CoreData

enum ModelContainerFactoryError: LocalizedError {
    case sharedStoreLoadFailed(storeURL: URL, underlyingErrorDescription: String)

    private var isLegacyUnversionedStoreError: Bool {
        switch self {
        case let .sharedStoreLoadFailed(_, underlyingErrorDescription):
            return Self.isLegacyUnversionedStoreError(underlyingErrorDescription)
        }
    }

    static func isLegacyUnversionedStoreError(_ description: String) -> Bool {
        let normalizedDescription = description.lowercased()
        return normalizedDescription.contains("unknown coordinator model version") ||
            normalizedDescription.contains("unknown model version")
    }

    static func isLegacyUnversionedStoreError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134504 {
            return true
        }

        if Self.isLegacyUnversionedStoreError(nsError.localizedDescription) {
            return true
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           Self.isLegacyUnversionedStoreError(underlyingError.localizedDescription) {
            return true
        }

        return Self.isLegacyUnversionedStoreError(String(describing: error))
    }

    var failureReason: String {
        switch self {
        case .sharedStoreLoadFailed:
            if isLegacyUnversionedStoreError {
                return "This store was created before FitNotes started versioning its SwiftData schema, so iOS can't perform a staged migration for it."
            }

            return "FitNotes couldn't open the current SwiftData store with the active schema."
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .sharedStoreLoadFailed:
            if isLegacyUnversionedStoreError {
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
    static let schema = Schema(versionedSchema: AppSchemaV3.self)

    static func makeSharedContainer(storeURL: URL? = nil) throws -> ModelContainer {
        let resolvedStoreURL = try storeURL ?? defaultStoreURL()
        let configuration = ModelConfiguration(url: resolvedStoreURL)
        do {
            return try makeVersionedContainer(configuration: configuration)
        } catch let versionedError {
            let versionedErrorDescription = detailedErrorDescription(for: versionedError)
            let isLegacyUnversionedStore = isLegacyUnversionedStore(at: resolvedStoreURL) ||
                ModelContainerFactoryError.isLegacyUnversionedStoreError(versionedError)

            if isLegacyUnversionedStore {
                throw ModelContainerFactoryError.sharedStoreLoadFailed(
                    storeURL: resolvedStoreURL,
                    underlyingErrorDescription: """
                    Cannot use staged migration with an unknown model version.
                    \(versionedErrorDescription)
                    """
                )
            }

            throw ModelContainerFactoryError.sharedStoreLoadFailed(
                storeURL: resolvedStoreURL,
                underlyingErrorDescription: versionedErrorDescription
            )
        }
    }

    private static func detailedErrorDescription(for error: Error) -> String {
        let nsError = error as NSError
        let candidateDescriptions = [
            String(describing: error),
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion,
            (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription
        ]

        var uniqueDescriptions: [String] = []
        for candidate in candidateDescriptions {
            guard let trimmedCandidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmedCandidate.isEmpty,
                  !uniqueDescriptions.contains(trimmedCandidate) else {
                continue
            }
            uniqueDescriptions.append(trimmedCandidate)
        }

        return uniqueDescriptions.joined(separator: "\n")
    }

    private static func isLegacyUnversionedStore(at storeURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return false
        }

        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        ) else {
            return false
        }

        if let identifiers = metadata[NSStoreModelVersionIdentifiersKey] as? [String] {
            return identifiers.isEmpty
        }

        if let identifiers = metadata[NSStoreModelVersionIdentifiersKey] as? Set<String> {
            return identifiers.isEmpty
        }

        return metadata[NSStoreModelVersionIdentifiersKey] == nil
    }

    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try makeVersionedContainer(configuration: configuration)
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
        let sidecarExtensions = ["", "-shm", "-wal", "-journal"]

        for suffix in sidecarExtensions {
            let candidateURL = suffix.isEmpty ? storeURL : URL(fileURLWithPath: storeURL.path + suffix)
            if FileManager.default.fileExists(atPath: candidateURL.path()) {
                try FileManager.default.removeItem(at: candidateURL)
            }
        }
    }

    private static func makeVersionedContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [configuration]
        )
    }

}
