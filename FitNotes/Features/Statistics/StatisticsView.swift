import Charts
import SwiftUI
import SwiftData

struct StatisticsView: View {
    @Query(
        filter: #Predicate<Workout> { workout in
            workout.finishedAt != nil
        },
        sort: [SortDescriptor(\Workout.startedAt)]
    )
    private var completedWorkouts: [Workout]

    @State private var selectedExerciseID: PersistentIdentifier?
    @State private var selectedMetric: ExerciseProgressionMetric = .maxWeight
    @State private var selectedRange: StatisticsTimeRange = .last90Days
    @State private var selectedGranularity: ExerciseProgressionGranularity = .week

    private var statistics: WorkoutStatisticsSnapshot {
        WorkoutStatisticsSnapshot(workouts: completedWorkouts)
    }

    private var selectedRecord: ExercisePersonalRecord? {
        if let selectedExerciseID,
           let record = statistics.personalRecords.first(where: { $0.exerciseID == selectedExerciseID }) {
            return record
        }

        return statistics.personalRecords.first
    }

    private var progressionPoints: [ExerciseProgressionPoint] {
        guard let exerciseID = selectedRecord?.exerciseID else {
            return []
        }

        return statistics.progression(
            for: exerciseID,
            metric: selectedMetric,
            range: selectedRange,
            granularity: selectedGranularity
        )
    }

    private var progressionSummary: ExerciseProgressionSummary {
        guard let exerciseID = selectedRecord?.exerciseID else {
            return .empty
        }

        return statistics.progressionSummary(
            for: exerciseID,
            metric: selectedMetric,
            range: selectedRange,
            granularity: selectedGranularity
        )
    }

    var body: some View {
        List {
            if completedWorkouts.isEmpty {
                ContentUnavailableView(
                    "No stats yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Finish a workout to unlock exercise progression tracking.")
                )
            } else {
                Section("Overview") {
                    LabeledContent("Completed Workouts") {
                        Text("\(statistics.completedWorkoutCount)")
                    }

                    LabeledContent("Tracked Sets") {
                        Text("\(statistics.totalSetCount)")
                    }

                    LabeledContent("Exercises Tracked") {
                        Text("\(statistics.uniqueExerciseCount)")
                    }

                    LabeledContent("Lifetime Volume") {
                        Text(volumeString(statistics.lifetimeVolume))
                    }

                    LabeledContent("Heaviest Weight") {
                        Text(weightString(statistics.heaviestWeight))
                    }
                }

                Section("Progression Settings") {
                    if !statistics.personalRecords.isEmpty {
                        Picker("Exercise", selection: exerciseSelectionBinding) {
                            ForEach(statistics.personalRecords) { record in
                                Text(record.exerciseName).tag(record.exerciseID)
                            }
                        }
                    }

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
                }

                Section("Exercise Progression") {
                    if let selectedRecord {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedRecord.exerciseName)
                                .font(.headline)
                            Text(selectedRecord.muscleGroupName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    if progressionPoints.isEmpty {
                        ContentUnavailableView(
                            "No data in this range",
                            systemImage: "chart.line.flattrend.xyaxis",
                            description: Text("Try a wider time range or a different exercise.")
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
                        .frame(height: 240)

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

                        LabeledContent("Buckets") {
                            Text("\(progressionSummary.pointCount)")
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
        .navigationTitle("Statistics")
        .onAppear {
            syncSelection()
        }
        .onChange(of: statistics.personalRecords.map(\.exerciseID)) { _, _ in
            syncSelection()
        }
    }

    private var exerciseSelectionBinding: Binding<PersistentIdentifier> {
        let fallback = statistics.personalRecords.first?.exerciseID

        return Binding(
            get: { selectedRecord?.exerciseID ?? fallback ?? selectedExerciseID ?? statistics.personalRecords.first!.exerciseID },
            set: { selectedExerciseID = $0 }
        )
    }

    private func syncSelection() {
        guard !statistics.personalRecords.isEmpty else {
            selectedExerciseID = nil
            return
        }

        if let selectedExerciseID,
           statistics.personalRecords.contains(where: { $0.exerciseID == selectedExerciseID }) {
            return
        }

        selectedExerciseID = statistics.personalRecords.first?.exerciseID
    }

    private func weightString(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) kg"
    }

    private func volumeString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...0))) + " kg·reps"
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

    private func signedMetricString(_ value: Double, metric: ExerciseProgressionMetric) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + metricString(value, metric: metric)
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
    }
    .modelContainer(ModelContainerFactory.makeInMemoryContainer())
}
