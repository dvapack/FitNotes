import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showingFileImporter = false
    @State private var selectedFileName: String?
    @State private var preview: FitNotesImportPreview?
    @State private var importResult: FitNotesImportResult?
    @State private var errorMessage: String?

    private var importer: FitNotesCSVImporter {
        FitNotesCSVImporter(context: modelContext)
    }

    var body: some View {
        List {
            Section("FitNotes CSV") {
                Text("Import workouts from a FitNotes CSV export. Supported columns are Date, Exercise, Category, Weight, Weight Unit, and Reps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Choose CSV File") {
                    showingFileImporter = true
                }

                if let selectedFileName {
                    LabeledContent("Selected File") {
                        Text(selectedFileName)
                            .lineLimit(1)
                    }
                }
            }

            if let preview {
                Section("Preview Summary") {
                    LabeledContent("Workouts") {
                        Text("\(preview.workoutCount)")
                    }

                    LabeledContent("Exercises") {
                        Text("\(preview.exerciseCount)")
                    }

                    LabeledContent("Valid Sets") {
                        Text("\(preview.rows.count)")
                    }

                    LabeledContent("Skipped Rows") {
                        Text("\(preview.skippedRowCount)")
                    }

                    Button("Import Data") {
                        commitImport(preview)
                    }
                }

                Section("Preview Rows") {
                    ForEach(Array(preview.rows.prefix(10))) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.exerciseName)
                                .font(.headline)
                            Text(row.categoryName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(row.date.formatted(date: .abbreviated, time: .omitted)) • \(row.weight.formatted(.number.precision(.fractionLength(0...2)))) kg x \(row.reps)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    if preview.rows.count > 10 {
                        Text("Showing the first 10 rows from the validated import preview.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No import preview yet",
                        systemImage: "square.and.arrow.down",
                        description: Text("Choose a CSV file to validate it and preview the import summary before saving.")
                    )
                }
            }

            if let importResult {
                Section("Last Import") {
                    LabeledContent("Imported Workouts") {
                        Text("\(importResult.importedWorkoutCount)")
                    }

                    LabeledContent("Imported Sets") {
                        Text("\(importResult.importedSetCount)")
                    }

                    LabeledContent("Skipped Rows") {
                        Text("\(importResult.skippedRowCount)")
                    }
                }
            }
        }
        .navigationTitle("Import")
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .alert("Import Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            preview = try importer.previewImport(from: data)
            importResult = nil
            selectedFileName = url.lastPathComponent
        } catch {
            preview = nil
            importResult = nil
            selectedFileName = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The selected file could not be imported."
        }
    }

    private func commitImport(_ preview: FitNotesImportPreview) {
        do {
            importResult = try importer.importPreview(preview)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The import could not be completed."
        }
    }
}

#Preview {
    NavigationStack {
        ImportView()
    }
}
