import Charts
import SwiftData
import SwiftUI

private struct BodyMeasurementTemplate: Identifiable {
    let id = UUID()
    let name: String
    let unitSymbol: String
}

struct BodyTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AppSettings.createdAt)])
    private var appSettings: [AppSettings]
    @Query(sort: [SortDescriptor(\BodyMeasurementMetric.sortOrder), SortDescriptor(\BodyMeasurementMetric.name)])
    private var metrics: [BodyMeasurementMetric]

    @State private var draftMetricTemplate: BodyMeasurementTemplate?
    @State private var editingMetric: BodyMeasurementMetric?
    @State private var errorMessage: String?

    private var settings: AppSettingsSnapshot {
        AppSettingsSnapshot(settings: appSettings.first)
    }

    private var snapshot: BodyTrackingSnapshot {
        BodyTrackingSnapshot(metrics: metrics, calendar: settings.calendar())
    }

    private var enabledMetrics: [BodyMeasurementMetric] {
        metrics.filter(\.isEnabled)
    }

    private var disabledMetrics: [BodyMeasurementMetric] {
        metrics.filter { !$0.isEnabled }
    }

    var body: some View {
        List {
            overviewSection

            if metrics.isEmpty {
                emptyStateSection
            } else {
                enabledMeasurementsSection

                if !disabledMetrics.isEmpty {
                    disabledMeasurementsSection
                }
            }
        }
        .navigationTitle("Body Tracking")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Add", systemImage: "plus") {
                    ForEach(defaultTemplates) { template in
                        Button(template.name) {
                            draftMetricTemplate = template
                        }
                    }

                    Divider()

                    Button("Custom Measurement") {
                        draftMetricTemplate = BodyMeasurementTemplate(name: "", unitSymbol: "")
                    }
                }
            }

            if !enabledMetrics.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(item: $draftMetricTemplate) { template in
            BodyMeasurementMetricEditorSheet(
                metric: nil,
                initialName: template.name,
                initialUnitSymbol: template.unitSymbol
            )
        }
        .sheet(item: $editingMetric) { metric in
            BodyMeasurementMetricEditorSheet(metric: metric)
        }
        .alert("Body Tracking Error", isPresented: Binding(
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

    private var overviewSection: some View {
        Section("Overview") {
            LabeledContent("Active Measurements") {
                Text("\(snapshot.enabledMetricCount)")
            }

            LabeledContent("Saved Entries") {
                Text("\(snapshot.totalEntryCount)")
            }

            if let latestEntryDate = snapshot.latestEntryDate {
                LabeledContent("Latest Check-In") {
                    Text(latestEntryDate.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if !snapshot.latestValues.isEmpty {
                ForEach(snapshot.latestValues.prefix(3)) { latestValue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(latestValue.metricName)
                            .font(.headline)
                        Text("\(formattedValue(latestValue.value)) \(latestValue.unitSymbol)")
                        Text(latestValue.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var emptyStateSection: some View {
        Section {
            ContentUnavailableView(
                "No body measurements yet",
                systemImage: "figure.arms.open",
                description: Text("Add body weight, waist, body fat, or any custom metric to start tracking history and goals.")
            )
        }
    }

    private var enabledMeasurementsSection: some View {
        Section("Measurements") {
            ForEach(enabledMetrics) { metric in
                NavigationLink {
                    BodyMeasurementDetailView(metric: metric)
                } label: {
                    BodyMeasurementRow(metric: metric, snapshot: snapshot)
                }
                .swipeActions {
                    Button("Edit") {
                        editingMetric = metric
                    }
                    .tint(.blue)
                }
            }
            .onMove(perform: moveMetrics)
        }
    }

    private var disabledMeasurementsSection: some View {
        Section("Disabled") {
            ForEach(disabledMetrics) { metric in
                NavigationLink {
                    BodyMeasurementDetailView(metric: metric)
                } label: {
                    BodyMeasurementRow(metric: metric, snapshot: snapshot)
                }
                .swipeActions {
                    Button("Edit") {
                        editingMetric = metric
                    }
                    .tint(.blue)
                }
            }
        }
    }

    private var defaultTemplates: [BodyMeasurementTemplate] {
        let bodyWeightUnit = settings.unitSystem == .pounds ? "lb" : "kg"
        return [
            BodyMeasurementTemplate(name: "Body Weight", unitSymbol: bodyWeightUnit),
            BodyMeasurementTemplate(name: "Body Fat", unitSymbol: "%"),
            BodyMeasurementTemplate(name: "Waist", unitSymbol: "cm"),
            BodyMeasurementTemplate(name: "Chest", unitSymbol: "cm")
        ]
    }

    private func moveMetrics(fromOffsets: IndexSet, toOffset: Int) {
        do {
            try BodyMeasurementStore(context: modelContext).moveMeasurements(fromOffsets: fromOffsets, toOffset: toOffset)
        } catch {
            errorMessage = error.userFacingMessage(
                fallback: "The measurement order could not be updated."
            )
        }
    }

    private func formattedValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct BodyMeasurementRow: View {
    let metric: BodyMeasurementMetric
    let snapshot: BodyTrackingSnapshot

    private var latestValue: BodyMeasurementLatestValue? {
        snapshot.latestValues.first(where: { $0.metricID == metric.persistentModelID })
    }

    private var goalStatus: BodyMeasurementGoalStatus? {
        snapshot.goalStatus(for: metric)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.name)
                    .font(.headline)
                if !metric.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let latestValue {
                Text("\(latestValue.value.formatted(.number.precision(.fractionLength(0...2)))) \(metric.unitSymbol)")
                Text(latestValue.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No entries yet")
                    .foregroundStyle(.secondary)
            }

            if let goalStatus {
                ProgressView(value: goalStatus.progress)
                    .tint(goalStatus.isAchieved ? .green : .accentColor)
                Text(goalStatus.statusText)
                    .font(.caption)
                    .foregroundStyle(goalStatus.isAchieved ? Color.green : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct BodyMeasurementDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AppSettings.createdAt)])
    private var appSettings: [AppSettings]

    let metric: BodyMeasurementMetric

    @State private var selectedRange: StatisticsTimeRange = .last90Days
    @State private var selectedGranularity: ExerciseProgressionGranularity = .week
    @State private var showingEntryEditor = false
    @State private var editingEntry: BodyMeasurementEntry?
    @State private var showingMetricEditor = false
    @State private var errorMessage: String?

    private var settings: AppSettingsSnapshot {
        AppSettingsSnapshot(settings: appSettings.first)
    }

    private var snapshot: BodyTrackingSnapshot {
        BodyTrackingSnapshot(metrics: [metric], calendar: settings.calendar())
    }

    private var points: [BodyMeasurementHistoryPoint] {
        snapshot.progression(for: metric, range: selectedRange, granularity: selectedGranularity)
    }

    private var summary: BodyMeasurementHistorySummary {
        snapshot.summary(for: metric, range: selectedRange, granularity: selectedGranularity)
    }

    private var goalStatus: BodyMeasurementGoalStatus? {
        snapshot.goalStatus(for: metric)
    }

    private var sortedEntries: [BodyMeasurementEntry] {
        metric.entries.sorted(using: [KeyPathComparator(\BodyMeasurementEntry.recordedAt, order: .reverse)])
    }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Unit") {
                    Text(metric.unitSymbol)
                }

                LabeledContent("Status") {
                    Text(metric.isEnabled ? "Active" : "Disabled")
                }

                if let latest = sortedEntries.first {
                    LabeledContent("Latest Value") {
                        Text(valueString(latest.value))
                    }
                }

                LabeledContent("Entries") {
                    Text("\(sortedEntries.count)")
                }
            }

            Section("History Settings") {
                Picker("Time Range", selection: $selectedRange) {
                    ForEach(StatisticsTimeRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }

                Picker("Grouping", selection: $selectedGranularity) {
                    ForEach(ExerciseProgressionGranularity.allCases) { granularity in
                        Text(granularity.title).tag(granularity)
                    }
                }
            }

            Section("Trend") {
                if points.isEmpty {
                    ContentUnavailableView(
                        "No entries yet",
                        systemImage: "chart.line.flattrend.xyaxis",
                        description: Text("Save a measurement to unlock the body-history chart.")
                    )
                } else {
                    Chart(points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value(metric.name, point.averageValue)
                        )
                        .foregroundStyle(.orange.opacity(0.18))

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(metric.name, point.averageValue)
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(metric.name, point.averageValue)
                        )
                        .foregroundStyle(.orange)
                    }
                    .frame(height: 220)

                    LabeledContent("Current") {
                        Text(valueString(summary.currentValue))
                    }

                    LabeledContent("Change From Start") {
                        Text(signedValueString(summary.changeFromStart))
                            .foregroundStyle(
                                summary.changeFromStart == 0
                                    ? Color.secondary
                                    : (summary.changeFromStart > 0 ? Color.green : Color.red)
                            )
                    }

                    LabeledContent("Lowest") {
                        Text(valueString(summary.lowestValue))
                    }

                    LabeledContent("Highest") {
                        Text(valueString(summary.highestValue))
                    }
                }
            }

            Section("Goal") {
                if let goalStatus {
                    LabeledContent("Direction") {
                        Text(goalStatus.direction.title)
                    }

                    LabeledContent("Target") {
                        Text(valueString(goalStatus.targetValue))
                    }

                    LabeledContent("Current") {
                        Text(valueString(goalStatus.currentValue))
                    }

                    ProgressView(value: goalStatus.progress)
                        .tint(goalStatus.isAchieved ? .green : .accentColor)

                    Text(goalStatus.statusText)
                        .font(.subheadline)
                        .foregroundStyle(goalStatus.isAchieved ? Color.green : Color.secondary)

                    if !metric.goalNotes.isEmpty {
                        Text(metric.goalNotes)
                            .font(.subheadline)
                    }
                } else {
                    Text("Add an optional increase or decrease target for this metric.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Entries") {
                Button("Log Measurement") {
                    editingEntry = nil
                    showingEntryEditor = true
                }

                ForEach(sortedEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(valueString(entry.value))
                            .font(.headline)
                        Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 2)
                    .swipeActions {
                        Button("Edit") {
                            editingEntry = entry
                            showingEntryEditor = true
                        }
                        .tint(.blue)

                        Button("Delete", role: .destructive) {
                            delete(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingMetricEditor = true
                }
            }
        }
        .sheet(isPresented: $showingEntryEditor) {
            BodyMeasurementEntryEditorSheet(metric: metric, entry: editingEntry)
        }
        .sheet(isPresented: $showingMetricEditor) {
            BodyMeasurementMetricEditorSheet(metric: metric)
        }
        .alert("Body Tracking Error", isPresented: Binding(
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

    private func delete(_ entry: BodyMeasurementEntry) {
        do {
            try BodyMeasurementStore(context: modelContext).deleteEntry(entry)
        } catch {
            errorMessage = error.userFacingMessage(
                fallback: "The measurement entry could not be deleted."
            )
        }
    }

    private func valueString(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(metric.unitSymbol)"
    }

    private func signedValueString(_ value: Double) -> String {
        let number = value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(0...2)))
        return "\(number) \(metric.unitSymbol)"
    }
}

private struct BodyMeasurementMetricEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let metric: BodyMeasurementMetric?

    @State private var name: String
    @State private var unitSymbol: String
    @State private var isEnabled: Bool
    @State private var usesGoal: Bool
    @State private var goalDirection: BodyMeasurementGoalDirection
    @State private var goalTargetValue: String
    @State private var goalNotes: String
    @State private var errorMessage: String?

    init(metric: BodyMeasurementMetric?, initialName: String? = nil, initialUnitSymbol: String? = nil) {
        self.metric = metric
        _name = State(initialValue: metric?.name ?? initialName ?? "")
        _unitSymbol = State(initialValue: metric?.unitSymbol ?? initialUnitSymbol ?? "")
        _isEnabled = State(initialValue: metric?.isEnabled ?? true)
        _usesGoal = State(initialValue: metric?.hasGoal ?? false)
        _goalDirection = State(initialValue: metric?.goalDirection ?? .decrease)
        _goalTargetValue = State(initialValue: metric?.goalTargetValue.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "")
        _goalNotes = State(initialValue: metric?.goalNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Measurement") {
                    TextField("Name", text: $name)
                    TextField("Unit", text: $unitSymbol)
                    Toggle("Enabled", isOn: $isEnabled)
                }

                Section("Goal") {
                    Toggle("Track Goal", isOn: $usesGoal.animation())

                    if usesGoal {
                        Picker("Direction", selection: $goalDirection) {
                            ForEach(BodyMeasurementGoalDirection.allCases) { direction in
                                Text(direction.title).tag(direction)
                            }
                        }

                        TextField("Target Value", text: $goalTargetValue)
                            .keyboardType(.decimalPad)

                        TextField("Notes", text: $goalNotes, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let metric {
                    Section {
                        Button("Delete Measurement", role: .destructive) {
                            delete(metric)
                        }
                    }
                }
            }
            .navigationTitle(metric == nil ? "New Measurement" : "Edit Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
        .alert("Measurement Error", isPresented: Binding(
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

    private func save() {
        let parsedTarget = Double(goalTargetValue.replacingOccurrences(of: ",", with: "."))
        let direction = usesGoal ? goalDirection : nil
        let target = usesGoal ? parsedTarget : nil

        do {
            let store = BodyMeasurementStore(context: modelContext)
            if let metric {
                try store.updateMeasurement(
                    metric,
                    name: name,
                    unitSymbol: unitSymbol,
                    isEnabled: isEnabled,
                    goalDirection: direction,
                    goalTargetValue: target,
                    goalNotes: goalNotes
                )
            } else {
                _ = try store.createMeasurement(
                    name: name,
                    unitSymbol: unitSymbol,
                    isEnabled: isEnabled,
                    goalDirection: direction,
                    goalTargetValue: target,
                    goalNotes: goalNotes
                )
            }

            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The measurement could not be saved."
        }
    }

    private func delete(_ metric: BodyMeasurementMetric) {
        do {
            try BodyMeasurementStore(context: modelContext).deleteMeasurement(metric)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The measurement could not be deleted."
        }
    }
}

private struct BodyMeasurementEntryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let metric: BodyMeasurementMetric
    let entry: BodyMeasurementEntry?

    @State private var value: String
    @State private var recordedAt: Date
    @State private var note: String
    @State private var errorMessage: String?

    init(metric: BodyMeasurementMetric, entry: BodyMeasurementEntry?) {
        self.metric = metric
        self.entry = entry
        _value = State(initialValue: entry?.value.formatted(.number.precision(.fractionLength(0...2))) ?? "")
        _recordedAt = State(initialValue: entry?.recordedAt ?? .now)
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Measurement") {
                    TextField("Value (\(metric.unitSymbol))", text: $value)
                        .keyboardType(.decimalPad)
                    DatePicker("Recorded At", selection: $recordedAt)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(entry == nil ? "Log Measurement" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
        .alert("Entry Error", isPresented: Binding(
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

    private func save() {
        let parsedValue = Double(value.replacingOccurrences(of: ",", with: "."))

        guard let parsedValue else {
            errorMessage = BodyMeasurementStoreError.invalidValue.errorDescription
            return
        }

        do {
            let store = BodyMeasurementStore(context: modelContext)
            if let entry {
                try store.updateEntry(entry, value: parsedValue, recordedAt: recordedAt, note: note)
            } else {
                _ = try store.addEntry(to: metric, value: parsedValue, recordedAt: recordedAt, note: note)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The measurement entry could not be saved."
        }
    }
}
