import SwiftUI

struct PersistenceRecoveryView: View {
    let error: AppBootstrapError
    let onRetry: () -> Void
    let onReset: () -> Void

    @State private var showingResetConfirmation = false

    private var storePath: String? {
        error.storeURL?.path
    }

    private var canReset: Bool {
        error.storeURL != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local Data Needs Recovery")
                            .font(.title2.bold())
                        Text("FitNotes couldn't finish loading its local data, so your existing data has been left in place.")
                            .foregroundStyle(.secondary)
                    }

                    if let storePath {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Store Path")
                                .font(.headline)
                            Text(storePath)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next Steps")
                            .font(.headline)
                        Text(error.recoverySuggestion)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why This Happened")
                            .font(.headline)
                        Text(error.failureReason)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button("Try Again", action: onRetry)
                            .buttonStyle(.borderedProminent)

                        if canReset {
                            Button("Reset Local Data", role: .destructive) {
                                showingResetConfirmation = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("FitNotes")
        }
        .alert("Reset local data?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive, action: onReset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the current on-device FitNotes store files so the app can create a new empty store.")
        }
    }
}
