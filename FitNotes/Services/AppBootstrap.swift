import Foundation
import Combine
import SwiftData

enum AppBootstrapError: LocalizedError {
    case storeLoad(ModelContainerFactoryError)
    case dataPreparationFailed(storeURL: URL?, step: String, underlyingErrorDescription: String)

    var storeURL: URL? {
        switch self {
        case let .storeLoad(error):
            switch error {
            case let .sharedStoreLoadFailed(storeURL, _):
                return storeURL
            }
        case let .dataPreparationFailed(storeURL, _, _):
            return storeURL
        }
    }

    var failureReason: String {
        switch self {
        case let .storeLoad(error):
            return error.failureReason
        case let .dataPreparationFailed(_, step, _):
            return "FitNotes opened the local store, but it couldn't \(step) during startup."
        }
    }

    var recoverySuggestion: String {
        switch self {
        case let .storeLoad(error):
            return error.recoverySuggestion
        case .dataPreparationFailed:
            return "Try reopening the store first. If startup still fails and you don't need the current on-device data, you can reset local storage and start fresh."
        }
    }

    var errorDescription: String? {
        switch self {
        case let .storeLoad(error):
            return error.localizedDescription
        case let .dataPreparationFailed(storeURL, step, underlyingErrorDescription):
            let pathDescription = storeURL?.path ?? "an unknown path"
            return """
            FitNotes couldn't finish startup work for its local data store at \(pathDescription).
            Step: \(step)
            \(underlyingErrorDescription)
            """
        }
    }
}

@MainActor
final class AppBootstrap: ObservableObject {
    enum State {
        case ready(ModelContainer)
        case failed(AppBootstrapError)
    }

    @Published private(set) var state: State

    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let container = ModelContainerFactory.makeInMemoryContainer()
            try? Self.prepareInitialData(in: container, storeURL: nil)
            state = .ready(container)
        } else {
            state = Self.loadSharedState()
        }
    }

    func reload() {
        state = Self.loadSharedState()
    }

    func resetStoreAndReload() {
        guard case let .failed(error) = state, let storeURL = error.storeURL else {
            return
        }

        try? ModelContainerFactory.resetStoreFiles(at: storeURL)
        state = Self.loadSharedState()
    }

    private static func loadSharedState() -> State {
        do {
            let container = try ModelContainerFactory.makeSharedContainer()
            try prepareInitialData(in: container, storeURL: try? ModelContainerFactory.defaultStoreURL())
            return .ready(container)
        } catch {
            if let error = error as? AppBootstrapError {
                return .failed(error)
            }

            if let error = error as? ModelContainerFactoryError {
                return .failed(.storeLoad(error))
            }

            return .failed(.dataPreparationFailed(
                storeURL: try? ModelContainerFactory.defaultStoreURL(),
                step: "complete startup preparation",
                underlyingErrorDescription: String(describing: error)
            ))
        }
    }

    private static func prepareInitialData(in container: ModelContainer, storeURL: URL?) throws {
        let seeder = SeedDataService(context: container.mainContext)
        do {
            try seeder.seedIfNeeded()
        } catch {
            throw AppBootstrapError.dataPreparationFailed(
                storeURL: storeURL,
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
                step: "repair existing local workout data",
                underlyingErrorDescription: String(describing: error)
            )
        }
    }
}
