import SwiftUI
import SwiftData

@main
struct FitNotesApp: App {
    @StateObject private var appState = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch appState.state {
        case let .ready(container):
            ContentView()
                .modelContainer(container)
        case let .failed(error):
            PersistenceRecoveryView(
                error: error,
                resetErrorMessage: appState.resetErrorMessage,
                onDismissResetError: {
                    appState.resetErrorMessage = nil
                },
                onRetry: appState.reload,
                onReset: appState.resetStoreAndReload
            )
        }
    }
}
