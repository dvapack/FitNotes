import SwiftUI
import SwiftData

struct TrainingReviewContentView: View {
    private static let calendarDayCellHeight: CGFloat = 60
    private static let calendarGridSpacing: CGFloat = 10

    @Query(sort: [SortDescriptor(\AppSettings.createdAt)])
    private var appSettings: [AppSettings]
    let workouts: [Workout]
    let onDeleteWorkout: (Workout) -> Void

    @State private var selectedMode: TrainingReviewMode = .calendar
    @State private var selectedMonthAnchor: Date
    @State private var selectedDate: Date
    @State private var selectedMuscleGroupID: PersistentIdentifier?
    @State private var selectedExerciseID: PersistentIdentifier?

    init(workouts: [Workout], onDeleteWorkout: @escaping (Workout) -> Void) {
        self.workouts = workouts
        self.onDeleteWorkout = onDeleteWorkout
        let latestDate = workouts.map(\.date).max() ?? .now
        _selectedMonthAnchor = State(initialValue: latestDate)
        _selectedDate = State(initialValue: latestDate)
    }

    private var snapshot: TrainingReviewSnapshot {
        let calendar = settings.calendar()
        return TrainingReviewSnapshot(workouts: workouts, calendar: calendar)
    }

    private var settings: AppSettingsSnapshot {
        AppSettingsSnapshot(settings: appSettings.first)
    }

    private var calendar: Calendar {
        settings.calendar()
    }

    private var filteredWorkouts: [Workout] {
        snapshot.filteredWorkouts(muscleGroupID: selectedMuscleGroupID, exerciseID: selectedExerciseID)
    }

    private var monthDays: [TrainingMonthDay] {
        snapshot.monthGrid(
            monthAnchor: selectedMonthAnchor,
            muscleGroupID: selectedMuscleGroupID,
            exerciseID: selectedExerciseID
        )
    }

    private var visibleMonthSummaries: [TrainingDaySummary] {
        snapshot.daySummaries(
            monthAnchor: selectedMonthAnchor,
            muscleGroupID: selectedMuscleGroupID,
            exerciseID: selectedExerciseID
        )
    }

    private var selectedDaySummary: TrainingDaySummary? {
        snapshot.selectedDaySummary(
            day: selectedDate,
            muscleGroupID: selectedMuscleGroupID,
            exerciseID: selectedExerciseID
        )
    }

    private var overview: TrainingReviewOverview {
        snapshot.overview(muscleGroupID: selectedMuscleGroupID, exerciseID: selectedExerciseID)
    }

    private var monthTitle: String {
        selectedMonthAnchor.formatted(.dateTime.month(.wide).year())
    }

    private var calendarGridHeight: CGFloat {
        let weekdayHeaderHeight: CGFloat = 18
        let weekRowCount = max(monthDays.count / 7, 1)
        return weekdayHeaderHeight
            + Self.calendarGridSpacing
            + (CGFloat(weekRowCount) * Self.calendarDayCellHeight)
            + (CGFloat(weekRowCount - 1) * Self.calendarGridSpacing)
    }

    var body: some View {
        List {
            if workouts.isEmpty {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("Finish a workout to unlock history review.")
                )
            } else {
                modeSection
                filtersSection
                overviewSection

                if filteredWorkouts.isEmpty {
                    ContentUnavailableView(
                        "No matching workouts",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try clearing the active filters.")
                    )
                } else if selectedMode == .calendar {
                    calendarSection
                    selectedDaySection
                    selectedExerciseSection
                } else {
                    listSection
                }
            }
        }
        .onAppear {
            syncSelection()
        }
        .onChange(of: selectedMuscleGroupID) { _, newValue in
            let availableExerciseIDs = Set(snapshot.availableExercises(filteredBy: newValue).map(\.id))
            if let selectedExerciseID, !availableExerciseIDs.contains(selectedExerciseID) {
                self.selectedExerciseID = nil
            }
            syncSelection()
        }
        .onChange(of: selectedExerciseID) { _, _ in
            syncSelection()
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Review Mode", selection: $selectedMode) {
                ForEach(TrainingReviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var filtersSection: some View {
        Section("Filters") {
            Picker("Muscle Group", selection: $selectedMuscleGroupID) {
                Text("All Muscle Groups").tag(Optional<PersistentIdentifier>.none)
                ForEach(snapshot.availableMuscleGroups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }

            Picker("Exercise", selection: $selectedExerciseID) {
                Text("All Exercises").tag(Optional<PersistentIdentifier>.none)
                ForEach(snapshot.availableExercises(filteredBy: selectedMuscleGroupID)) { exercise in
                    Text("\(exercise.name) • \(exercise.muscleGroupName)").tag(Optional(exercise.id))
                }
            }
        }
    }

    private var overviewSection: some View {
        Section("Training Review") {
            LabeledContent("Workouts") {
                Text("\(overview.workoutCount)")
            }

            LabeledContent("Sets") {
                Text("\(overview.setCount)")
            }

            LabeledContent("Active Days") {
                Text("\(overview.activeDays)")
            }

            LabeledContent("Workouts / Week") {
                Text(overview.averageWorkoutsPerWeek.formatted(.number.precision(.fractionLength(1))))
            }

            LabeledContent("Current Streak") {
                Text(streakText(overview.currentWorkoutDayStreak))
            }

            LabeledContent("Longest Streak") {
                Text(streakText(overview.longestWorkoutDayStreak))
            }
        }
    }

    private var calendarSection: some View {
        Section {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()
                Text(monthTitle)
                    .font(.headline)
                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                ForEach(Array(settings.orderedVeryShortWeekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                }

                ForEach(monthDays) { day in
                    MonthDayCell(
                        day: day,
                        isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate)
                    ) {
                        selectedDate = day.date
                    }
                }
            }
            .frame(height: calendarGridHeight)
            .padding(.vertical, 4)
        } header: {
            Text("Calendar")
        } footer: {
            if visibleMonthSummaries.isEmpty {
                Text("No workouts match the current filters this month.")
            } else {
                Text("\(visibleMonthSummaries.count) active days in \(monthTitle).")
            }
        }
    }

    private var selectedDaySection: some View {
        Section(selectedDaySectionTitle) {
            if let selectedDaySummary {
                dayOverviewView(summary: selectedDaySummary)

                ForEach(selectedDaySummary.workouts) { workout in
                    NavigationLink {
                        WorkoutHistoryDetailView(workout: workout)
                    } label: {
                        WorkoutHistoryRow(workout: workout)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            onDeleteWorkout(workout)
                        }
                    }
                }
            } else {
                Text("No workouts on this day.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedExerciseSection: some View {
        Section("Exercises On This Day") {
            if let selectedDaySummary, !selectedDaySummary.exerciseSummaries.isEmpty {
                ForEach(selectedDaySummary.exerciseSummaries) { summary in
                    if let exercise = summary.exercise {
                        NavigationLink {
                            ExerciseInsightsView(exercise: exercise)
                        } label: {
                            dayExerciseRow(summary: summary)
                        }
                    } else {
                        dayExerciseRow(summary: summary)
                    }
                }
            } else {
                Text("No exercises match the current filters on this day.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var listSection: some View {
        Section("List View") {
            ForEach(snapshot.daySummaries(muscleGroupID: selectedMuscleGroupID, exerciseID: selectedExerciseID)) { summary in
                VStack(alignment: .leading, spacing: 10) {
                    dayOverviewView(summary: summary)

                    ForEach(summary.workouts) { workout in
                        NavigationLink {
                            WorkoutHistoryDetailView(workout: workout)
                        } label: {
                            WorkoutHistoryRow(workout: workout)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                onDeleteWorkout(workout)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var selectedDaySectionTitle: String {
        "Selected Day: " + selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func dayOverviewView(summary: TrainingDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.headline)
                    Text("\(summary.workoutCount) workouts • \(summary.setCount) sets • \(summary.exerciseCount) exercises")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(Array(summary.accentColorHexes.prefix(4).enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 10, height: 10)
                    }
                }
            }

            Text(settings.formatVolume(summary.totalVolume))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dayExerciseRow(summary: TrainingDayExerciseSummary) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: summary.colorHex))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.exerciseName)
                Text(summary.muscleGroupName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(summary.setCount) sets")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func shiftMonth(by value: Int) {
        selectedMonthAnchor = calendar.date(byAdding: .month, value: value, to: selectedMonthAnchor) ?? selectedMonthAnchor
        if let latestVisibleDay = visibleMonthSummaries.first?.date {
            selectedDate = latestVisibleDay
        } else if let monthInterval = calendar.dateInterval(of: .month, for: selectedMonthAnchor) {
            selectedDate = monthInterval.start
        }
    }

    private func syncSelection() {
        if let latestFilteredDate = snapshot.latestWorkoutDate(
            muscleGroupID: selectedMuscleGroupID,
            exerciseID: selectedExerciseID
        ) {
            if snapshot.selectedDaySummary(
                day: selectedDate,
                muscleGroupID: selectedMuscleGroupID,
                exerciseID: selectedExerciseID
            ) == nil {
                selectedDate = latestFilteredDate
            }

            selectedMonthAnchor = latestFilteredDate
        }
    }

    private func streakText(_ value: Int) -> String {
        value == 1 ? "1 day" : "\(value) days"
    }
}

private enum TrainingReviewMode: String, CaseIterable, Identifiable {
    case calendar
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            return "Calendar"
        case .list:
            return "List"
        }
    }
}

private struct WorkoutHistoryRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            Text(workoutSummary(for: workout))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !workout.comment.isEmpty {
                Text(workout.comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func workoutSummary(for workout: Workout) -> String {
        let exerciseCount = Set(workout.sets.compactMap { $0.exercise?.persistentModelID }).count
        return "\(workout.sets.count) sets across \(exerciseCount) exercises"
    }
}

private struct MonthDayCell: View {
    private static let fixedHeight: CGFloat = 60

    let day: TrainingMonthDay
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(day.date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(day.isInDisplayedMonth ? .primary : .secondary)

                if let summary = day.summary {
                    Text("\(summary.workoutCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 3) {
                        ForEach(Array(summary.accentColorHexes.prefix(3).enumerated()), id: \.offset) { _, hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 5, height: 5)
                        }
                    }
                } else {
                    Spacer()
                        .frame(height: 16)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .frame(height: Self.fixedHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        if isSelected {
            return .accentColor.opacity(0.16)
        }

        if day.summary != nil {
            return Color(.secondarySystemBackground)
        }

        return .clear
    }
}
