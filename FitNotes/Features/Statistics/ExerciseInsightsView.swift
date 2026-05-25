import Charts
import SwiftData
import SwiftUI

struct ExerciseInsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AppSettings.createdAt)])
    private var appSettings: [AppSettings]
    @Query(
        filter: #Predicate<Workout> { workout in
            workout.finishedAt != nil
        },
        sort: [SortDescriptor(\Workout.startedAt, order: .reverse)]
    )
    private var completedWorkouts: [Workout]

    let exercise: Exercise

    @State private var selectedMetric: ExerciseProgressionMetric
    @State private var selectedRange: StatisticsTimeRange = .last90Days
    @State private var selectedGranularity: ExerciseProgressionGranularity = .week
    @State private var showingGoalEditor = false

    init(exercise: Exercise) {
        self.exercise = exercise
        _selectedMetric = State(initialValue: ExerciseProgressionMetric(progressionView: exercise.defaultProgressionView))
    }

    private var settings: AppSettingsSnapshot {
        AppSettingsSnapshot(settings: appSettings.first)
    }

    private var statistics: WorkoutStatisticsSnapshot {
        WorkoutStatisticsSnapshot(workouts: completedWorkouts, calendar: settings.calendar())
    }

    private var personalRecord: ExercisePersonalRecord? {
        statistics.personalRecords.first(where: { $0.exerciseID == exercise.persistentModelID })
    }

    private var progressionPoints: [ExerciseProgressionPoint] {
        statistics.progression(
            for: exercise.persistentModelID,
            metric: selectedMetric,
            range: selectedRange,
            granularity: selectedGranularity
        )
    }

    private var progressionSummary: ExerciseProgressionSummary {
        statistics.progressionSummary(
            for: exercise.persistentModelID,
            metric: selectedMetric,
            range: selectedRange,
            granularity: selectedGranularity
        )
    }

    private var historyEntries: [ExerciseWorkoutHistoryEntry] {
        let finishedSets = exercise.workoutSets.filter { $0.workout?.finishedAt != nil }
        let groupedSets = Dictionary(grouping: finishedSets) { $0.workout?.persistentModelID }

        return groupedSets.values.compactMap { sets in
            guard let workout = sets.first?.workout else { return nil }
            let sortedSets = sets.sorted { lhs, rhs in
                if lhs.setOrder != rhs.setOrder {
                    return lhs.setOrder < rhs.setOrder
                }

                return lhs.weight < rhs.weight
            }

            let totalVolume = sortedSets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            let totalReps = sortedSets.reduce(0) { $0 + $1.reps }
            let maxWeight = sortedSets.map(\.weight).max() ?? 0

            return ExerciseWorkoutHistoryEntry(
                workout: workout,
                sets: sortedSets,
                totalVolume: totalVolume,
                totalReps: totalReps,
                maxWeight: maxWeight
            )
        }
        .sorted { $0.workout.startedAt > $1.workout.startedAt }
    }

    private var recordHighlights: ExerciseRecordHighlights {
        let bestSessionVolume = historyEntries.map(\.totalVolume).max() ?? 0
        let bestSessionReps = historyEntries.map(\.totalReps).max() ?? 0
        let estimatedOneRepMax: Double?

        if exercise.exerciseType == .weightReps {
            estimatedOneRepMax = exercise.workoutSets
                .filter { $0.workout?.finishedAt != nil }
                .map { $0.weight * (1 + (Double($0.reps) / 30)) }
                .max()
        } else {
            estimatedOneRepMax = nil
        }

        return ExerciseRecordHighlights(
            heaviestWeight: personalRecord?.maxWeight ?? 0,
            estimatedOneRepMax: estimatedOneRepMax,
            bestSessionVolume: bestSessionVolume,
            bestSessionReps: bestSessionReps,
            workoutCount: personalRecord?.workoutCount ?? 0,
            setCount: personalRecord?.setCount ?? 0,
            totalVolume: personalRecord?.totalVolume ?? 0,
            lastPerformedAt: personalRecord?.lastPerformedAt
        )
    }

    private var goalStatus: ExerciseGoalStatus? {
        guard
            let metric = exercise.goalMetric,
            let targetValue = exercise.goalTargetValue,
            targetValue > 0
        else {
            return nil
        }

        let currentValue: Double
        switch metric {
        case .maxWeight:
            currentValue = recordHighlights.heaviestWeight
        case .totalVolume:
            currentValue = recordHighlights.bestSessionVolume
        case .totalReps:
            currentValue = Double(recordHighlights.bestSessionReps)
        }

        return ExerciseGoalStatus(
            metric: metric,
            targetValue: targetValue,
            currentValue: currentValue,
            notes: exercise.goalNotes
        )
    }

    var body: some View {
        List {
            overviewSection
            recordsSection
            goalSection
            progressionSection
            historySection
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(goalStatus == nil ? "Add Goal" : "Edit Goal") {
                    showingGoalEditor = true
                }
            }
        }
        .sheet(isPresented: $showingGoalEditor) {
            ExerciseGoalEditorSheet(exercise: exercise)
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            LabeledContent("Muscle Group") {
                Text(exercise.muscleGroup?.name ?? "Uncategorized")
            }

            LabeledContent("Tracking") {
                Text(exercise.exerciseType.title)
            }

            LabeledContent("Preferred Unit") {
                Text(exercise.preferredWeightUnit.title)
            }

            LabeledContent("Default Rest") {
                Text(exercise.defaultRestSeconds > 0 ? "\(exercise.defaultRestSeconds)s" : "Off")
            }

            if !exercise.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(exercise.notes)
                }
                .padding(.top, 4)
            }
        }
    }

    private var recordsSection: some View {
        Section("Record Highlights") {
            if historyEntries.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "chart.line.flattrend.xyaxis",
                    description: Text("Log this exercise in a finished workout to unlock records and progression.")
                )
            } else {
                LabeledContent("Heaviest Weight") {
                    Text(weightString(recordHighlights.heaviestWeight))
                }

                if settings.personalRecordBehavior == .includeEstimatedOneRepMax,
                   let estimatedOneRepMax = recordHighlights.estimatedOneRepMax {
                    LabeledContent("Estimated 1RM") {
                        Text(weightString(estimatedOneRepMax))
                    }
                }

                LabeledContent("Best Session Volume") {
                    Text(volumeString(recordHighlights.bestSessionVolume))
                }

                LabeledContent("Best Session Reps") {
                    Text("\(recordHighlights.bestSessionReps)")
                }

                LabeledContent("Completed Workouts") {
                    Text("\(recordHighlights.workoutCount)")
                }

                LabeledContent("Tracked Sets") {
                    Text("\(recordHighlights.setCount)")
                }

                LabeledContent("Lifetime Volume") {
                    Text(volumeString(recordHighlights.totalVolume))
                }

                if let lastPerformedAt = recordHighlights.lastPerformedAt {
                    LabeledContent("Last Performed") {
                        Text(lastPerformedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        Section("Goal") {
            if let goalStatus {
                LabeledContent("Metric") {
                    Text(goalStatus.metric.title)
                }

                LabeledContent("Target") {
                    Text(goalMetricString(goalStatus.targetValue, metric: goalStatus.metric))
                }

                LabeledContent("Current Best") {
                    Text(goalMetricString(goalStatus.currentValue, metric: goalStatus.metric))
                }

                ProgressView(value: goalStatus.progress)
                    .tint(goalStatus.isAchieved ? .green : .accentColor)

                Text(goalStatus.statusText)
                    .font(.subheadline)
                    .foregroundStyle(goalStatus.isAchieved ? .green : .secondary)

                if !goalStatus.notes.isEmpty {
                    Text(goalStatus.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "No goal yet",
                    systemImage: "target",
                    description: Text("Set a target for max weight, session volume, or session reps.")
                )
            }
        }
    }

    private var progressionSection: some View {
        Section("Progression") {
            if historyEntries.isEmpty {
                ContentUnavailableView(
                    "No progression yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Finish workouts with this exercise to populate a progression chart.")
                )
            } else {
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(ExerciseProgressionMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }

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

                if progressionPoints.isEmpty {
                    ContentUnavailableView(
                        "No data in this range",
                        systemImage: "chart.line.flattrend.xyaxis",
                        description: Text("Try a wider range or a different progression metric.")
                    )
                } else {
                    Chart(progressionPoints) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value(selectedMetric.title, point.value)
                        )
                        .foregroundStyle(.green.opacity(0.18))

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(selectedMetric.title, point.value)
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(selectedMetric.title, point.value)
                        )
                        .foregroundStyle(.green)
                    }
                    .frame(height: 220)

                    LabeledContent("Best in Range") {
                        Text(metricString(progressionSummary.bestValue, metric: selectedMetric))
                    }

                    LabeledContent("Most Recent") {
                        Text(metricString(progressionSummary.recentValue, metric: selectedMetric))
                    }

                    LabeledContent("Change From Start") {
                        Text(signedMetricString(progressionSummary.changeFromFirst, metric: selectedMetric))
                            .foregroundStyle(progressionSummary.changeFromFirst >= 0 ? .green : .red)
                    }

                    LabeledContent("Tracked Workouts") {
                        Text("\(progressionSummary.workoutCount)")
                    }

                    LabeledContent("Sets in Range") {
                        Text("\(progressionSummary.setCount)")
                    }

                    LabeledContent("Reps in Range") {
                        Text("\(progressionSummary.totalReps)")
                    }

                    LabeledContent("Volume in Range") {
                        Text(volumeString(progressionSummary.totalVolume))
                    }
                }
            }
        }
    }

    private var historySection: some View {
        Section("Workout History") {
            if historyEntries.isEmpty {
                Text("This exercise has not appeared in a finished workout yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(historyEntries) { entry in
                    NavigationLink {
                        WorkoutHistoryDetailView(workout: entry.workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)

                            Text("\(entry.sets.count) sets • \(weightString(entry.maxWeight)) • \(volumeString(entry.totalVolume))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ForEach(entry.sets.prefix(3)) { workoutSet in
                                Text("Set \(workoutSet.setOrder): \(weightString(workoutSet.weight)) x \(workoutSet.reps)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func weightString(_ value: Double) -> String {
        settings.formatWeight(value)
    }

    private func volumeString(_ value: Double) -> String {
        settings.formatVolume(value)
    }

    private func metricString(_ value: Double, metric: ExerciseProgressionMetric) -> String {
        switch metric {
        case .maxWeight, .averageWeight:
            return weightString(value)
        case .totalVolume:
            return volumeString(value)
        case .totalReps, .setCount:
            return value.formatted(.number.precision(.fractionLength(0...0)))
        }
    }

    private func goalMetricString(_ value: Double, metric: ExerciseProgressionView) -> String {
        switch metric {
        case .maxWeight:
            return weightString(value)
        case .totalVolume:
            return volumeString(value)
        case .totalReps:
            return value.formatted(.number.precision(.fractionLength(0...0)))
        }
    }

    private func signedMetricString(_ value: Double, metric: ExerciseProgressionMetric) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + metricString(value, metric: metric)
    }
}

private struct ExerciseWorkoutHistoryEntry: Identifiable {
    let workout: Workout
    let sets: [WorkoutSet]
    let totalVolume: Double
    let totalReps: Int
    let maxWeight: Double

    var id: PersistentIdentifier {
        workout.persistentModelID
    }
}

private struct ExerciseRecordHighlights {
    let heaviestWeight: Double
    let estimatedOneRepMax: Double?
    let bestSessionVolume: Double
    let bestSessionReps: Int
    let workoutCount: Int
    let setCount: Int
    let totalVolume: Double
    let lastPerformedAt: Date?
}

private struct ExerciseGoalStatus {
    let metric: ExerciseProgressionView
    let targetValue: Double
    let currentValue: Double
    let notes: String

    var remainingValue: Double {
        max(targetValue - currentValue, 0)
    }

    var progress: Double {
        min(max(currentValue / targetValue, 0), 1)
    }

    var isAchieved: Bool {
        currentValue >= targetValue
    }

    var statusText: String {
        if isAchieved {
            return "Goal reached"
        }

        switch metric {
        case .maxWeight:
            return "\(remainingValue.formatted(.number.precision(.fractionLength(0...2)))) left to hit the target."
        case .totalVolume, .totalReps:
            return "\(remainingValue.formatted(.number.precision(.fractionLength(0...0)))) left to hit the target."
        }
    }
}

private struct ExerciseGoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let exercise: Exercise

    @State private var selectedMetric: ExerciseProgressionView
    @State private var targetValueText: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(exercise: Exercise) {
        self.exercise = exercise
        _selectedMetric = State(initialValue: exercise.goalMetric ?? exercise.defaultProgressionView)
        _targetValueText = State(initialValue: exercise.goalTargetValue.map {
            $0.formatted(.number.precision(.fractionLength(0...2)))
        } ?? "")
        _notes = State(initialValue: exercise.goalNotes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(ExerciseProgressionView.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }

                    TextField("Target", text: $targetValueText)
                        .keyboardType(.decimalPad)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button("Clear Goal", role: .destructive) {
                        clearGoal()
                    }
                }
            }
            .navigationTitle(exercise.hasGoal ? "Edit Goal" : "Add Goal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveGoal()
                    }
                }
            }
            .alert("Unable to save goal", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveGoal() {
        guard let targetValue = Double(targetValueText.replacingOccurrences(of: ",", with: ".")), targetValue > 0 else {
            errorMessage = "Enter a target greater than zero."
            return
        }

        exercise.goalMetric = selectedMetric
        exercise.goalTargetValue = targetValue
        exercise.goalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearGoal() {
        exercise.goalMetric = nil
        exercise.goalTargetValue = nil
        exercise.goalNotes = ""

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension ExerciseProgressionMetric {
    init(progressionView: ExerciseProgressionView) {
        switch progressionView {
        case .maxWeight:
            self = .maxWeight
        case .totalVolume:
            self = .totalVolume
        case .totalReps:
            self = .totalReps
        }
    }
}

#Preview {
    let container = ModelContainerFactory.makeInMemoryContainer()
    let context = ModelContext(container)
    let group = MuscleGroup(name: "Chest", sortOrder: 0)
    let exercise = Exercise(name: "Bench Press", normalizedName: "bench press", isCustom: false, muscleGroup: group)
    context.insert(group)
    context.insert(exercise)

    return NavigationStack {
        ExerciseInsightsView(exercise: exercise)
    }
    .modelContainer(container)
}
