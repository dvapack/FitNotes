import Foundation
import SwiftData

enum StatisticsTimeRange: String, CaseIterable, Identifiable {
    case last30Days
    case last90Days
    case last180Days
    case last365Days
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last30Days:
            return "30 Days"
        case .last90Days:
            return "90 Days"
        case .last180Days:
            return "6 Months"
        case .last365Days:
            return "1 Year"
        case .allTime:
            return "All Time"
        }
    }

    func startDate(relativeTo latestDate: Date, calendar: Calendar) -> Date? {
        switch self {
        case .last30Days:
            return calendar.date(byAdding: .day, value: -29, to: latestDate)
        case .last90Days:
            return calendar.date(byAdding: .day, value: -89, to: latestDate)
        case .last180Days:
            return calendar.date(byAdding: .day, value: -179, to: latestDate)
        case .last365Days:
            return calendar.date(byAdding: .day, value: -364, to: latestDate)
        case .allTime:
            return nil
        }
    }
}

enum ExerciseProgressionMetric: String, CaseIterable, Identifiable {
    case maxWeight
    case averageWeight
    case totalVolume
    case totalReps
    case setCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maxWeight:
            return "Max Weight"
        case .averageWeight:
            return "Average Weight"
        case .totalVolume:
            return "Volume"
        case .totalReps:
            return "Reps"
        case .setCount:
            return "Sets"
        }
    }
}

enum ExerciseProgressionGranularity: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            return "Daily"
        case .week:
            return "Weekly"
        case .month:
            return "Monthly"
        }
    }
}

struct ExercisePersonalRecord: Identifiable {
    let exerciseID: PersistentIdentifier
    let exerciseName: String
    let muscleGroupName: String
    let maxWeight: Double
    let totalVolume: Double
    let setCount: Int
    let workoutCount: Int
    let lastPerformedAt: Date

    var id: PersistentIdentifier { exerciseID }
}

struct ExerciseProgressionPoint: Identifiable {
    let date: Date
    let value: Double
    let setCount: Int
    let reps: Int
    let volume: Double
    let workoutCount: Int

    var id: Date { date }
}

struct ExerciseProgressionSummary {
    let pointCount: Int
    let workoutCount: Int
    let setCount: Int
    let totalReps: Int
    let totalVolume: Double
    let bestValue: Double
    let recentValue: Double
    let changeFromFirst: Double

    static let empty = ExerciseProgressionSummary(
        pointCount: 0,
        workoutCount: 0,
        setCount: 0,
        totalReps: 0,
        totalVolume: 0,
        bestValue: 0,
        recentValue: 0,
        changeFromFirst: 0
    )
}

struct WorkoutStatisticsSnapshot {
    let completedWorkoutCount: Int
    let totalSetCount: Int
    let uniqueExerciseCount: Int
    let lifetimeVolume: Double
    let heaviestWeight: Double
    let personalRecords: [ExercisePersonalRecord]

    private let latestWorkoutDate: Date?
    private let setsByExerciseID: [PersistentIdentifier: [WorkoutSet]]
    private let calendar: Calendar

    static let empty = WorkoutStatisticsSnapshot(
        completedWorkoutCount: 0,
        totalSetCount: 0,
        uniqueExerciseCount: 0,
        lifetimeVolume: 0,
        heaviestWeight: 0,
        personalRecords: [],
        latestWorkoutDate: nil,
        setsByExerciseID: [:],
        calendar: .current
    )

    private init(
        completedWorkoutCount: Int,
        totalSetCount: Int,
        uniqueExerciseCount: Int,
        lifetimeVolume: Double,
        heaviestWeight: Double,
        personalRecords: [ExercisePersonalRecord],
        latestWorkoutDate: Date?,
        setsByExerciseID: [PersistentIdentifier: [WorkoutSet]],
        calendar: Calendar
    ) {
        self.completedWorkoutCount = completedWorkoutCount
        self.totalSetCount = totalSetCount
        self.uniqueExerciseCount = uniqueExerciseCount
        self.lifetimeVolume = lifetimeVolume
        self.heaviestWeight = heaviestWeight
        self.personalRecords = personalRecords
        self.latestWorkoutDate = latestWorkoutDate
        self.setsByExerciseID = setsByExerciseID
        self.calendar = calendar
    }

    init(workouts: [Workout], calendar: Calendar = .current) {
        let completedWorkouts = workouts
            .filter { $0.finishedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }

        guard !completedWorkouts.isEmpty else {
            self = .empty
            return
        }

        let allSets = completedWorkouts.flatMap(\.sets)
        let setsByExerciseID = Dictionary(grouping: allSets) { set in
            set.exercise?.persistentModelID
        }
        .reduce(into: [PersistentIdentifier: [WorkoutSet]]()) { partialResult, entry in
            guard let exerciseID = entry.key else { return }
            partialResult[exerciseID] = entry.value
        }

        self.completedWorkoutCount = completedWorkouts.count
        self.totalSetCount = allSets.count
        self.uniqueExerciseCount = Set(allSets.compactMap { $0.exercise?.persistentModelID }).count
        self.lifetimeVolume = allSets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        self.heaviestWeight = allSets.map(\.weight).max() ?? 0
        self.personalRecords = WorkoutStatisticsSnapshot.makePersonalRecords(allSets: allSets)
        self.latestWorkoutDate = completedWorkouts.map(\.date).max()
        self.setsByExerciseID = setsByExerciseID
        self.calendar = calendar
    }

    func progression(
        for exerciseID: PersistentIdentifier,
        metric: ExerciseProgressionMetric,
        range: StatisticsTimeRange,
        granularity: ExerciseProgressionGranularity
    ) -> [ExerciseProgressionPoint] {
        guard var exerciseSets = setsByExerciseID[exerciseID] else {
            return []
        }

        if let latestWorkoutDate,
           let startDate = range.startDate(relativeTo: latestWorkoutDate, calendar: calendar) {
            let boundedStartDate = calendar.startOfDay(for: startDate)
            exerciseSets = exerciseSets.filter {
                guard let workoutDate = $0.workout?.date else { return false }
                return calendar.startOfDay(for: workoutDate) >= boundedStartDate
            }
        }

        let groupedByDate = Dictionary(grouping: exerciseSets) { set in
            bucketDate(for: set.workout?.date ?? set.workout?.startedAt ?? .distantPast, granularity: granularity)
        }

        return groupedByDate.keys.sorted().compactMap { date in
            guard let sets = groupedByDate[date], !sets.isEmpty else {
                return nil
            }

            let totalVolume = sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            let totalReps = sets.reduce(0) { $0 + $1.reps }
            let setCount = sets.count
            let workoutCount = Set(sets.compactMap { $0.workout?.persistentModelID }).count

            return ExerciseProgressionPoint(
                date: date,
                value: metricValue(for: sets, metric: metric),
                setCount: setCount,
                reps: totalReps,
                volume: totalVolume,
                workoutCount: workoutCount
            )
        }
    }

    func progressionSummary(
        for exerciseID: PersistentIdentifier,
        metric: ExerciseProgressionMetric,
        range: StatisticsTimeRange,
        granularity: ExerciseProgressionGranularity
    ) -> ExerciseProgressionSummary {
        let points = progression(for: exerciseID, metric: metric, range: range, granularity: granularity)
        guard !points.isEmpty else {
            return .empty
        }

        let recentValue = points.last?.value ?? 0
        let firstValue = points.first?.value ?? 0

        return ExerciseProgressionSummary(
            pointCount: points.count,
            workoutCount: points.reduce(0) { $0 + $1.workoutCount },
            setCount: points.reduce(0) { $0 + $1.setCount },
            totalReps: points.reduce(0) { $0 + $1.reps },
            totalVolume: points.reduce(0) { $0 + $1.volume },
            bestValue: points.map(\.value).max() ?? 0,
            recentValue: recentValue,
            changeFromFirst: recentValue - firstValue
        )
    }

    private func bucketDate(for date: Date, granularity: ExerciseProgressionGranularity) -> Date {
        switch granularity {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let components = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        case .month:
            let components = calendar.dateComponents([.calendar, .year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        }
    }

    private func metricValue(for sets: [WorkoutSet], metric: ExerciseProgressionMetric) -> Double {
        switch metric {
        case .maxWeight:
            return sets.map(\.weight).max() ?? 0
        case .averageWeight:
            let totalWeight = sets.reduce(0) { $0 + $1.weight }
            return totalWeight / Double(max(sets.count, 1))
        case .totalVolume:
            return sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        case .totalReps:
            return Double(sets.reduce(0) { $0 + $1.reps })
        case .setCount:
            return Double(sets.count)
        }
    }

    private static func makePersonalRecords(allSets: [WorkoutSet]) -> [ExercisePersonalRecord] {
        let groupedSets = Dictionary(grouping: allSets) { set in
            set.exercise?.persistentModelID
        }

        return groupedSets.compactMap { exerciseID, sets in
            guard
                let exerciseID,
                let exercise = sets.first?.exercise
            else {
                return nil
            }

            let workoutCount = Set(sets.compactMap { $0.workout?.persistentModelID }).count
            let lastPerformedAt = sets.compactMap { $0.workout?.startedAt }.max() ?? .distantPast

            return ExercisePersonalRecord(
                exerciseID: exerciseID,
                exerciseName: exercise.name,
                muscleGroupName: exercise.muscleGroup?.name ?? "Uncategorized",
                maxWeight: sets.map(\.weight).max() ?? 0,
                totalVolume: sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) },
                setCount: sets.count,
                workoutCount: workoutCount,
                lastPerformedAt: lastPerformedAt
            )
        }
        .sorted {
            if $0.lastPerformedAt == $1.lastPerformedAt {
                return $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
            }

            return $0.lastPerformedAt > $1.lastPerformedAt
        }
    }
}
