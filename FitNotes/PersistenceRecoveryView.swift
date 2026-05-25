import SwiftUI

struct PersistenceRecoveryView: View {
    let error: AppBootstrapError
    let resetErrorMessage: String?
    let onDismissResetError: () -> Void
    let onRetry: () -> Void
    let onReset: (_ includeBackupStore: Bool) -> Void

    @State private var showingResetOptions = false

    private var storePath: String? {
        error.storeURL?.path
    }

    private var backupStorePath: String? {
        error.backupStoreURL?.path
    }

    private var canReset: Bool {
        error.storeURL != nil
    }

    private var canDeletePreservedBackup: Bool {
        error.backupStoreURL != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.recoveryTitle)
                            .font(.title2.bold())
                        Text(error.recoveryMessage)
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

                    if let backupStorePath {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preserved Backup")
                                .font(.headline)
                            Text(backupStorePath)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                            Text(error.backupStoreStillExists ? "The preserved backup files are still on disk." : "The preserved backup path was recorded, but the files are no longer present on disk.")
                                .foregroundStyle(.secondary)
                        }
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
                                showingResetOptions = true
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
        .confirmationDialog("Reset local data?", isPresented: $showingResetOptions, titleVisibility: .visible) {
            Button("Reset Current Store", role: .destructive) {
                onReset(false)
            }

            if canDeletePreservedBackup {
                Button("Reset and Delete Preserved Backup", role: .destructive) {
                    onReset(true)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(error.resetConfirmationMessage)
        }
        .alert("Reset Failed", isPresented: Binding(
            get: { resetErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    onDismissResetError()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                onDismissResetError()
            }
        } message: {
            Text(resetErrorMessage ?? "")
        }
    }
}
