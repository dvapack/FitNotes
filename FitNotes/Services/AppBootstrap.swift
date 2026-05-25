import Foundation
import Combine
import OSLog
import SwiftData

enum AppBootstrapError: LocalizedError {
    enum RecoveryContext: Equatable {
        case normalStartup
        case postLegacyRecovery(backupStoreURL: URL?)
    }

    enum Category: Equatable {
        case storeLoadFailure
        case legacyRecoveryFailed
        case postRecoveryPreparationFailed
    }

    case storeLoad(ModelContainerFactoryError)
    case legacyStoreRecoveryFailed(storeURL: URL, backupStoreURL: URL?, step: String, underlyingErrorDescription: String)
    case dataPreparationFailed(
        storeURL: URL?,
        recoveryContext: RecoveryContext,
        step: String,
        underlyingErrorDescription: String
    )

    var category: Category {
        switch self {
        case .storeLoad:
            return .storeLoadFailure
        case .legacyStoreRecoveryFailed:
            return .legacyRecoveryFailed
        case let .dataPreparationFailed(_, recoveryContext, _, _):
            switch recoveryContext {
            case .normalStartup:
                return .storeLoadFailure
            case .postLegacyRecovery:
                return .postRecoveryPreparationFailed
            }
        }
    }

    var storeURL: URL? {
        switch self {
        case let .storeLoad(error):
            switch error {
            case let .sharedStoreLoadFailed(storeURL, _):
                return storeURL
            }
        case let .legacyStoreRecoveryFailed(storeURL, _, _, _):
            return storeURL
        case let .dataPreparationFailed(storeURL, _, _, _):
            return storeURL
        }
    }

    var backupStoreURL: URL? {
        switch self {
        case .storeLoad:
            return nil
        case let .legacyStoreRecoveryFailed(_, backupStoreURL, _, _):
            return backupStoreURL
        case let .dataPreparationFailed(_, recoveryContext, _, _):
            switch recoveryContext {
            case .normalStartup:
                return nil
            case let .postLegacyRecovery(backupStoreURL):
                return backupStoreURL
            }
        }
    }

    var backupStoreStillExists: Bool {
        guard let backupStoreURL else {
            return false
        }

        return FileManager.default.fileExists(atPath: backupStoreURL.path)
    }

    var recoveryTitle: String {
        switch category {
        case .storeLoadFailure:
            return "Local Data Needs Recovery"
        case .legacyRecoveryFailed:
            return "Legacy Data Recovery Failed"
        case .postRecoveryPreparationFailed:
            return "Recovered Data Still Needs Attention"
        }
    }

    var recoveryMessage: String {
        switch category {
        case .storeLoadFailure:
            return "FitNotes couldn't finish loading its local data, so your existing data has been left in place."
        case .legacyRecoveryFailed:
            return "FitNotes found a legacy local store, kept a preserved backup, and stopped before replacing it with a partially recovered store."
        case .postRecoveryPreparationFailed:
            return "FitNotes recovered a legacy local store into the current format, but a later startup step still failed. Your recovered store is still on disk."
        }
    }

    var failureReason: String {
        switch self {
        case let .storeLoad(error):
            return error.failureReason
        case .legacyStoreRecoveryFailed:
            return "FitNotes found a legacy local store and couldn't finish importing it into the current app format."
        case let .dataPreparationFailed(_, recoveryContext, step, _):
            switch recoveryContext {
            case .normalStartup:
                return "FitNotes opened the local store, but it couldn't \(step) during startup."
            case .postLegacyRecovery:
                return "FitNotes recovered the legacy local store, but it couldn't \(step) during startup."
            }
        }
    }

    var recoverySuggestion: String {
        switch self {
        case let .storeLoad(error):
            return error.recoverySuggestion
        case let .legacyStoreRecoveryFailed(_, backupStoreURL, _, _):
            if let backupStoreURL {
                return "Your preserved legacy backup is still available at \(backupStoreURL.path). Keep a copy of those files before using Reset Local Data."
            }

            return "FitNotes couldn't finish importing the preserved legacy store. If you still need that data, make a copy of the current store files before using Reset Local Data."
        case let .dataPreparationFailed(_, recoveryContext, _, _):
            switch recoveryContext {
            case .normalStartup:
                return "Try reopening the store first. If startup still fails and you don't need the current on-device data, you can reset local storage and start fresh."
            case let .postLegacyRecovery(backupStoreURL):
                if let backupStoreURL {
                    return "Try reopening the recovered store first. If startup still fails, you can reset the current local store and keep the preserved backup at \(backupStoreURL.path), or explicitly delete both."
                }

                return "Try reopening the recovered store first. If startup still fails and you don't need the current on-device data, you can reset local storage and start fresh."
            }
        }
    }

    var errorDescription: String? {
        switch self {
        case let .storeLoad(error):
            return error.localizedDescription
        case let .legacyStoreRecoveryFailed(storeURL, backupStoreURL, step, underlyingErrorDescription):
            let backupDescription = backupStoreURL?.path ?? "No preserved backup path was recorded."
            return """
            FitNotes couldn't recover its legacy local data store at \(storeURL.path).
            Step: \(step)
            Preserved backup: \(backupDescription)
            \(underlyingErrorDescription)
            """
        case let .dataPreparationFailed(storeURL, recoveryContext, step, underlyingErrorDescription):
            let pathDescription = storeURL?.path ?? "an unknown path"
            let backupDescription: String
            switch recoveryContext {
            case .normalStartup:
                backupDescription = ""
            case let .postLegacyRecovery(backupStoreURL):
                let backupPath = backupStoreURL?.path ?? "No preserved backup path was recorded."
                backupDescription = "\nPreserved backup: \(backupPath)"
            }
            return """
            FitNotes couldn't finish startup work for its local data store at \(pathDescription).
            Step: \(step)
            \(backupDescription)
            \(underlyingErrorDescription)
            """
        }
    }

    var resetConfirmationMessage: String {
        if let backupStoreURL {
            return "This deletes the current on-device FitNotes store files. The preserved legacy backup at \(backupStoreURL.path) will stay on disk unless you explicitly choose to delete it too."
        }

        return "This deletes the current on-device FitNotes store files so the app can create a new empty store."
    }
}

@MainActor
final class AppBootstrap: ObservableObject {
    enum State {
        case ready(ModelContainer)
        case failed(AppBootstrapError)
    }

    @Published private(set) var state: State
    @Published var resetErrorMessage: String?

    static var startupPreparationDiagnosticHook: ((AppBootstrapError.RecoveryContext) throws -> Void)?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FitNotes",
        category: "AppBootstrap"
    )

    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let container = ModelContainerFactory.makeInMemoryContainer()
            try? Self.prepareInitialData(in: container, storeURL: nil, recoveryContext: .normalStartup)
            state = .ready(container)
        } else {
            state = Self.loadSharedState()
        }
    }

    func reload() {
        resetErrorMessage = nil
        state = Self.loadSharedState()
    }

    func resetStoreAndReload(includeBackupStore: Bool = false) {
        guard case let .failed(error) = state, let storeURL = error.storeURL else {
            return
        }

        Self.logger.notice(
            "Resetting store files at \(storeURL.path, privacy: .public). includeBackupStore=\(includeBackupStore, privacy: .public)"
        )
        do {
            try Self.resetStoreFiles(for: error, includeBackupStore: includeBackupStore)
            resetErrorMessage = nil
        } catch {
            let userFacingError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            Self.logger.error("Reset store files failed: \(userFacingError, privacy: .public)")
            resetErrorMessage = "FitNotes couldn't delete the local store files. \(userFacingError)"
            return
        }
        state = Self.loadSharedState()
    }

    static func resetStoreFiles(for error: AppBootstrapError, includeBackupStore: Bool) throws {
        if let storeURL = error.storeURL {
            try ModelContainerFactory.resetStoreFiles(at: storeURL)
        }

        guard includeBackupStore, let backupStoreURL = error.backupStoreURL else {
            return
        }

        try ModelContainerFactory.resetStoreFiles(at: backupStoreURL)
    }

    static func loadSharedState(storeURL: URL? = nil) -> State {
        do {
            let resolvedStoreURL = try storeURL ?? ModelContainerFactory.defaultStoreURL()
            logger.notice("Starting shared store bootstrap at \(resolvedStoreURL.path, privacy: .public)")
            return try loadSharedState(at: resolvedStoreURL)
        } catch {
            if let error = error as? AppBootstrapError {
                logger.error("Bootstrap failed: \(error.localizedDescription, privacy: .public)")
                return .failed(error)
            }

            if let error = error as? ModelContainerFactoryError {
                logger.error("Bootstrap store load failed: \(error.localizedDescription, privacy: .public)")
                return .failed(.storeLoad(error))
            }

            let resolvedStoreURL = storeURL ?? (try? ModelContainerFactory.defaultStoreURL())
            logger.error("Bootstrap preparation failed: \(String(describing: error), privacy: .public)")
            return .failed(.dataPreparationFailed(
                storeURL: resolvedStoreURL,
                recoveryContext: .normalStartup,
                step: "complete startup preparation",
                underlyingErrorDescription: String(describing: error)
            ))
        }
    }

    private static func loadSharedState(at storeURL: URL) throws -> State {
        do {
            let container = try ModelContainerFactory.makeSharedContainer(storeURL: storeURL)
            logger.notice("Opened shared store without legacy recovery at \(storeURL.path, privacy: .public)")
            try prepareInitialData(in: container, storeURL: storeURL, recoveryContext: .normalStartup)
            logger.notice("Finished startup preparation for \(storeURL.path, privacy: .public)")
            return .ready(container)
        } catch let error as ModelContainerFactoryError {
            guard case let .sharedStoreLoadFailed(_, description) = error,
                  ModelContainerFactoryError.isLegacyUnversionedStoreError(description) else {
                throw error
            }

            do {
                logger.notice("Detected legacy unversioned store at \(storeURL.path, privacy: .public); starting recovery")
                let recoveryResult = try LegacyStoreRecoveryService.recoverStore(at: storeURL)
                logger.notice(
                    "Legacy recovery created preserved backup at \(recoveryResult.backupStoreURL.path, privacy: .public)"
                )
                let container = try ModelContainerFactory.makeSharedContainer(storeURL: storeURL)
                logger.notice("Opened recovered shared store at \(storeURL.path, privacy: .public)")
                try prepareInitialData(
                    in: container,
                    storeURL: storeURL,
                    recoveryContext: .postLegacyRecovery(backupStoreURL: recoveryResult.backupStoreURL)
                )
                logger.notice("Finished post-recovery startup preparation for \(storeURL.path, privacy: .public)")
                return .ready(container)
            } catch let recoveryError as LegacyStoreRecoveryError {
                switch recoveryError {
                case let .sourceStoreMissing(missingStoreURL):
                    throw AppBootstrapError.legacyStoreRecoveryFailed(
                        storeURL: missingStoreURL,
                        backupStoreURL: nil,
                        step: "locate the legacy store",
                        underlyingErrorDescription: recoveryError.localizedDescription
                    )
                case let .recoveryFailed(backupStoreURL, step, underlyingErrorDescription):
                    throw AppBootstrapError.legacyStoreRecoveryFailed(
                        storeURL: storeURL,
                        backupStoreURL: backupStoreURL,
                        step: step,
                        underlyingErrorDescription: underlyingErrorDescription
                    )
                }
            }
        }
    }

    private static func prepareInitialData(
        in container: ModelContainer,
        storeURL: URL?,
        recoveryContext: AppBootstrapError.RecoveryContext
    ) throws {
        let seeder = SeedDataService(context: container.mainContext)
        do {
            try seeder.seedIfNeeded()
        } catch {
            throw AppBootstrapError.dataPreparationFailed(
                storeURL: storeURL,
                recoveryContext: recoveryContext,
                step: "seed the default exercise catalog",
                underlyingErrorDescription: String(describing: error)
            )
        }

        let backfillService = LegacyDataBackfillService(context: container.mainContext)
        do {
            _ = try backfillService.backfillIfNeeded()
        } catch {
            throw AppBootstrapError.dataPreparationFailed(
                storeURL: storeURL,
                recoveryContext: recoveryContext,
                step: "repair existing local workout data",
                underlyingErrorDescription: String(describing: error)
            )
        }

        do {
            try startupPreparationDiagnosticHook?(recoveryContext)
        } catch {
            throw AppBootstrapError.dataPreparationFailed(
                storeURL: storeURL,
                recoveryContext: recoveryContext,
                step: "finish startup diagnostics",
                underlyingErrorDescription: String(describing: error)
            )
        }
    }
}
