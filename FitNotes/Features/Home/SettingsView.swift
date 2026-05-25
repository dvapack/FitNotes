import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private enum ResetAction {
        case workouts
        case allData
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AppSettings.createdAt)])
    private var allSettings: [AppSettings]

    @State private var backupDocument = BackupFileDocument(data: Data())
    @State private var csvDocument = WorkoutCSVFileDocument(data: Data())
    @State private var backupFileName = "FitNotes Backup"
    @State private var csvFileName = "FitNotes Workouts"
    @State private var showingBackupExporter = false
    @State private var showingCSVExporter = false
    @State private var showingRestoreImporter = false
    @State private var pendingRestoreData: Data?
    @State private var pendingRestorePreview: BackupPreview?
    @State private var restoreFileName: String?
    @State private var pendingResetAction: ResetAction?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var settings: AppSettings? {
        allSettings.first
    }

    private var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(settings: settings)
    }

    private var dataPortabilityService: DataPortabilityService {
        DataPortabilityService(context: modelContext)
    }

    var body: some View {
        List {
            if settings != nil {
                unitsSection
                workoutSection
                historySection
                recordsSection
                homeSection
                portabilitySection
                resetSection
            } else {
                ContentUnavailableView(
                    "Settings unavailable",
                    systemImage: "gearshape",
                    description: Text("FitNotes couldn't load the local settings record.")
                )
            }

            if let statusMessage {
                Section("Last Action") {
                    Text(statusMessage)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Settings")
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: backupFileName
        ) { result in
            handleExportCompletion(result, successMessage: "Full backup ready to save.")
        }
        .fileExporter(
            isPresented: $showingCSVExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: csvFileName
        ) { result in
            handleExportCompletion(result, successMessage: "Workout CSV ready to save.")
        }
        .fileImporter(
            isPresented: $showingRestoreImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleRestoreSelection(result)
        }
        .alert("Restore Backup?", isPresented: Binding(
            get: { pendingRestorePreview != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRestorePreview = nil
                    pendingRestoreData = nil
                    restoreFileName = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                commitRestore()
            }
        } message: {
            if let preview = pendingRestorePreview {
                Text(restoreConfirmationMessage(for: preview, fileName: restoreFileName))
            }
        }
        .confirmationDialog(
            "Reset Local Data",
            isPresented: Binding(
                get: { pendingResetAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingResetAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            switch pendingResetAction {
            case .workouts:
                Button("Delete Workouts and History", role: .destructive) {
                    performReset(.workouts)
                }
            case .allData:
                Button("Delete Entire App Data", role: .destructive) {
                    performReset(.allData)
                }
            case nil:
                EmptyView()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resetConfirmationMessage)
        }
        .alert("Settings Error", isPresented: Binding(
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

    private var unitsSection: some View {
        Section("Units") {
            Picker("Display Unit", selection: binding(\.unitSystem)) {
                ForEach(AppUnitSystem.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }

            Picker("Weight Increment", selection: binding(\.weightIncrement)) {
                ForEach(incrementOptions, id: \.self) { option in
                    Text("\(option.formatted(.number.precision(.fractionLength(0...2)))) \(snapshot.unitSystem.symbol)")
                        .tag(option)
                }
            }
        }
    }

    private var workoutSection: some View {
        Section("Workout Logging") {
            Picker("New Set Status", selection: binding(\.setCompletionBehavior)) {
                ForEach(SetCompletionBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }

            Picker("Next Set", selection: binding(\.nextSetBehavior)) {
                ForEach(NextSetBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }

            Toggle("Show Rest Timer", isOn: binding(\.showsRestTimer))
            Toggle("Keep Screen Awake During Workouts", isOn: binding(\.keepScreenAwakeDuringWorkout))
        }
    }

    private var historySection: some View {
        Section("History and Calendar") {
            Picker("Week Starts On", selection: binding(\.calendarWeekStart)) {
                ForEach(CalendarWeekStart.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        }
    }

    private var recordsSection: some View {
        Section("Personal Records") {
            Picker("PR Display", selection: binding(\.personalRecordBehavior)) {
                ForEach(PersonalRecordBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }
        }
    }

    private var homeSection: some View {
        Section("Home Screen") {
            Toggle("Show Overview Stats", isOn: binding(\.showsHomeOverview))
            Toggle("Show Recent Workouts", isOn: binding(\.showsRecentWorkouts))
        }
    }

    private var portabilitySection: some View {
        Section("Data Portability") {
            Text("Save a full local backup, export a spreadsheet-friendly workout log, or restore this device from a previous FitNotes backup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Save Full Backup") {
                exportFullBackup()
            }

            Button("Export Workout CSV") {
                exportWorkoutCSV()
            }

            Button("Restore From Backup") {
                showingRestoreImporter = true
            }
        }
    }

    private var resetSection: some View {
        Section("Reset Local Data") {
            Text("These actions delete data on this device. Restoring from a backup or exporting one first is recommended.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Reset Workouts and History", role: .destructive) {
                pendingResetAction = .workouts
            }

            Button("Reset Entire App", role: .destructive) {
                pendingResetAction = .allData
            }
        }
    }

    private var incrementOptions: [Double] {
        switch snapshot.unitSystem {
        case .kilograms:
            return [1, 2.5, 5, 10]
        case .pounds:
            return [2.5, 5, 10, 15]
        }
    }

    private func exportFullBackup() {
        do {
            backupDocument = BackupFileDocument(data: try dataPortabilityService.exportBackupData())
            backupFileName = "FitNotes Backup \(Self.fileStampFormatter.string(from: .now))"
            showingBackupExporter = true
            statusMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The full backup could not be created."
        }
    }

    private func exportWorkoutCSV() {
        do {
            csvDocument = WorkoutCSVFileDocument(data: try dataPortabilityService.exportWorkoutCSV(using: snapshot))
            csvFileName = "FitNotes Workouts \(Self.fileStampFormatter.string(from: .now))"
            showingCSVExporter = true
            statusMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The workout CSV could not be created."
        }
    }

    private func handleRestoreSelection(_ result: Result<[URL], Error>) {
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
            pendingRestorePreview = try dataPortabilityService.previewBackup(from: data)
            pendingRestoreData = data
            restoreFileName = url.lastPathComponent
            statusMessage = nil
        } catch {
            pendingRestorePreview = nil
            pendingRestoreData = nil
            restoreFileName = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The backup file could not be read."
        }
    }

    private func commitRestore() {
        guard let pendingRestoreData else { return }

        do {
            let result = try dataPortabilityService.restoreBackup(from: pendingRestoreData)
            statusMessage = "Restored \(result.workoutCount) workouts, \(result.setCount) sets, \(result.exerciseCount) exercises, \(result.muscleGroupCount) muscle groups, and \(result.bodyMeasurementEntryCount) body entries from backup."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The backup could not be restored."
        }

        pendingRestorePreview = nil
        self.pendingRestoreData = nil
        restoreFileName = nil
    }

    private func performReset(_ action: ResetAction) {
        do {
            let result: DataResetResult
            switch action {
            case .workouts:
                result = try dataPortabilityService.resetWorkouts()
                statusMessage = "Deleted \(result.deletedWorkoutCount) workouts and \(result.deletedSetCount) saved sets."
            case .allData:
                result = try dataPortabilityService.resetAllData()
                statusMessage = "Deleted local app data and restored the default catalog and settings."
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The reset action could not be completed."
        }

        pendingResetAction = nil
    }

    private func handleExportCompletion(_ result: Result<URL, Error>, successMessage: String) {
        switch result {
        case .success:
            statusMessage = successMessage
        case let .failure(error):
            if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
                break
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The export could not be completed."
        }
    }

    private func restoreConfirmationMessage(for preview: BackupPreview, fileName: String?) -> String {
        let fileLabel = fileName ?? "this backup"
        return "Replace current FitNotes data with \(fileLabel)? This will restore \(preview.workoutCount) workouts, \(preview.setCount) sets, \(preview.exerciseCount) exercises, \(preview.muscleGroupCount) muscle groups, and \(preview.bodyMeasurementEntryCount) body entries from \(preview.exportedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private var resetConfirmationMessage: String {
        switch pendingResetAction {
        case .workouts:
            return "This permanently deletes all saved workouts and workout history on this device. Exercises, muscle groups, and settings stay in place."
        case .allData:
            return "This permanently deletes workouts, history, custom exercises, muscle groups, body measurements, and settings on this device, then recreates the default catalog and settings."
        case nil:
            return ""
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings?[keyPath: keyPath] ?? fallbackValue(for: keyPath) },
            set: { newValue in
                guard let settings else { return }
                let previousValue = settings[keyPath: keyPath]

                do {
                    try ModelContextPersistence.perform(in: modelContext) {
                        settings[keyPath: keyPath] = newValue
                    } revert: {
                        settings[keyPath: keyPath] = previousValue
                    } save: {
                        try modelContext.save()
                    }
                } catch {
                    errorMessage = error.userFacingMessage(
                        fallback: "Your settings change could not be saved."
                    )
                }
            }
        )
    }

    private func fallbackValue<Value>(for keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Value {
        let defaults = AppSettings()
        return defaults[keyPath: keyPath]
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(ModelContainerFactory.makeInMemoryContainer())
}
