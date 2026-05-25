import Foundation
import SwiftData

struct TrainingReviewSnapshot {
    let workouts: [Workout]
    let calendar: Calendar

    init(workouts: [Workout], calendar: Calendar = .current) {
        self.workouts = workouts
            .filter { $0.finishedAt != nil }
            .sorted { $0.date > $1.date }
        self.calendar = calendar
    }

    var isEmpty: Bool {
        workouts.isEmpty
    }

    var availableMuscleGroups: [TrainingReviewMuscleGroupOption] {
        let grouped = Dictionary(grouping: workouts.flatMap(\.sets)) { set in
            set.exercise?.muscleGroup?.persistentModelID
        }

        return grouped.compactMap { key, sets in
            guard
                let key,
                let muscleGroup = sets.first?.exercise?.muscleGroup
            else {
                return nil
            }

            return TrainingReviewMuscleGroupOption(
                id: key,
                name: muscleGroup.name,
                colorHex: muscleGroup.colorHex ?? "#4F7A28"
            )
        }
        .sorted {
            return $0.name < $1.name
        }
    }

    func availableExercises(filteredBy muscleGroupID: PersistentIdentifier?) -> [TrainingReviewExerciseOption] {
        let matchingSets = workouts
            .flatMap(\.sets)
            .filter { set in
                guard let exercise = set.exercise else { return false }
                guard let muscleGroupID else { return true }
                return exercise.muscleGroup?.persistentModelID == muscleGroupID
            }

        let grouped = Dictionary(grouping: matchingSets) { $0.exercise?.persistentModelID }
        return grouped.compactMap { key, sets in
            guard
                let key,
                let exercise = sets.first?.exercise
            else {
                return nil
            }

            return TrainingReviewExerciseOption(
                id: key,
                name: exercise.name,
                muscleGroupName: exercise.muscleGroup?.name ?? "Uncategorized"
            )
        }
        .sorted {
            if $0.muscleGroupName == $1.muscleGroupName {
                return $0.name < $1.name
            }

            return $0.muscleGroupName < $1.muscleGroupName
        }
    }

    func filteredWorkouts(
        muscleGroupID: PersistentIdentifier? = nil,
        exerciseID: PersistentIdentifier? = nil
    ) -> [Workout] {
        workouts.filter { workout in
            workoutMatchesFilters(workout, muscleGroupID: muscleGroupID, exerciseID: exerciseID)
        }
    }

    func overview(
        muscleGroupID: PersistentIdentifier? = nil,
        exerciseID: PersistentIdentifier? = nil
    ) -> TrainingReviewOverview {
        let filtered = filteredWorkouts(muscleGroupID: muscleGroupID, exerciseID: exerciseID)
        guard !filtered.isEmpty else {
            return .empty
        }

        let groupedDays = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        let orderedDays = groupedDays.keys.sorted()
        let firstDay = orderedDays.first ?? .now
        let lastDay = orderedDays.last ?? firstDay
        let daySpan = max(calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0, 0) + 1
        let weekSpan = max(Double(daySpan) / 7.0, 1)

        return TrainingReviewOverview(
            workoutCount: filtered.count,
            setCount: filtered.reduce(0) { partialResult, workout in
                partialResult + matchingSets(in: workout, muscleGroupID: muscleGroupID, exerciseID: exerciseID).count
            },
            activeDays: orderedDays.count,
            averageWorkoutsPerWeek: Double(filtered.count) / weekSpan,
            longestWorkoutDayStreak: longestStreak(in: orderedDays),
            currentWorkoutDayStreak: currentStreak(in: orderedDays)
        )
    }

    func daySummaries(
        monthAnchor: Date? = nil,
        muscleGroupID: PersistentIdentifier? = nil,
        exerciseID: PersistentIdentifier? = nil
    ) -> [TrainingDaySummary] {
        let filtered = filteredWorkouts(muscleGroupID: muscleGroupID, exerciseID: exerciseID)
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        let monthInterval = monthAnchor.flatMap { calendar.dateInterval(of: .month, for: $0) }

        return grouped.compactMap { day, workouts in
            if let monthInterval, !monthInterval.contains(day) {
                return nil
            }

            return makeDaySummary(
                for: day,
                workouts: workouts,
                muscleGroupID: muscleGroupID,
                exerciseID: exerciseID
            )
        }
        .sorted { $0.date > $1.date }
    }

    func monthGrid(
        monthAnchor: Date,
        muscleGroupID: PersistentIdentifier? = nil,
        exerciseID: PersistentIdentifier? = nil
    ) -> [TrainingMonthDay] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor),
            let monthStartWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        let summaries = Dictionary(uniqueKeysWithValues: daySummaries(
            monthAnchor: monthAnchor,
            muscleGroupID: muscleGroupID,
            exerciseID: exerciseID
        ).map { (calendar.startOfDay(for: $0.date), $0) })

        var result: [TrainingMonthDay] = []
        var currentDate = monthStartWeekInterval.start
        for _ in 0..<42 {
            result.append(TrainingMonthDay(
                date: currentDate,
                isInDisplayedMonth: monthInterval.contains(currentDate),
                summary: summaries[calendar.startOfDay(for: currentDate)]
            ))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return result
    }

    func selectedDaySummary(
        day: Date,
        muscleGroupID: PersistentIdentifier? = nil,
        exerciseID: PersistentIdentifier? = nil
    ) -> TrainingDaySummary? {
        let targetDay = calendar.startOfDay(for: day)
        return daySummaries(muscleGroupID: muscleGroupID, exerciseID: exerciseID)
            .first(where: { calendar.isDate($0.date, inSameDayAs: targetDay) })
    }

    func latestWorkoutDate(
        muscleGroupID: PersistentIdentifier? = nil,
        exerciseID: PersistentIdentifier? = nil
    ) -> Date? {
        filteredWorkouts(muscleGroupID: muscleGroupID, exerciseID: exerciseID).map(\.date).max()
    }

    private func makeDaySummary(
        for day: Date,
        workouts: [Workout],
        muscleGroupID: PersistentIdentifier?,
        exerciseID: PersistentIdentifier?
    ) -> TrainingDaySummary {
        let sortedWorkouts = workouts.sorted { $0.startedAt > $1.startedAt }
        let filteredSets = sortedWorkouts.flatMap { workout in
            matchingSets(in: workout, muscleGroupID: muscleGroupID, exerciseID: exerciseID)
        }
        let groupedSets = Dictionary(grouping: filteredSets) { set in
            set.exercise?.persistentModelID
        }

        let exerciseSummaries: [TrainingDayExerciseSummary] = groupedSets.values.compactMap { (sets: [WorkoutSet]) -> TrainingDayExerciseSummary? in
            let sortedSets = sets.sorted { lhs, rhs in
                if lhs.exerciseOrder != rhs.exerciseOrder {
                    return lhs.exerciseOrder < rhs.exerciseOrder
                }

                if lhs.setOrder != rhs.setOrder {
                    return lhs.setOrder < rhs.setOrder
                }

                return lhs.weight < rhs.weight
            }

            guard let firstSet = sortedSets.first else { return nil }

            return TrainingDayExerciseSummary(
                exercise: firstSet.exercise,
                exerciseName: firstSet.exercise?.name ?? firstSet.exerciseNameSnapshot ?? "Deleted Exercise",
                muscleGroupName: firstSet.exercise?.muscleGroup?.name ?? firstSet.muscleGroupNameSnapshot ?? "Uncategorized",
                colorHex: firstSet.exercise?.muscleGroup?.colorHex ?? "#4F7A28",
                setCount: sortedSets.count,
                workoutCount: Set(sortedSets.compactMap { $0.workout?.persistentModelID }).count
            )
        }
        .sorted {
            if $0.muscleGroupName == $1.muscleGroupName {
                return $0.exerciseName < $1.exerciseName
            }

            return $0.muscleGroupName < $1.muscleGroupName
        }

        return TrainingDaySummary(
            date: day,
            workouts: sortedWorkouts,
            workoutCount: sortedWorkouts.count,
            setCount: filteredSets.count,
            exerciseCount: exerciseSummaries.count,
            totalVolume: filteredSets.reduce(0) { $0 + ($1.weight * Double($1.reps)) },
            accentColorHexes: Array(Set(exerciseSummaries.map { $0.colorHex })).sorted(),
            exerciseSummaries: exerciseSummaries
        )
    }

    private func workoutMatchesFilters(
        _ workout: Workout,
        muscleGroupID: PersistentIdentifier?,
        exerciseID: PersistentIdentifier?
    ) -> Bool {
        !matchingSets(in: workout, muscleGroupID: muscleGroupID, exerciseID: exerciseID).isEmpty
    }

    private func matchingSets(
        in workout: Workout,
        muscleGroupID: PersistentIdentifier?,
        exerciseID: PersistentIdentifier?
    ) -> [WorkoutSet] {
        workout.sets.filter { set in
            if let exerciseID {
                return set.exercise?.persistentModelID == exerciseID
            }

            if let muscleGroupID {
                return set.exercise?.muscleGroup?.persistentModelID == muscleGroupID
            }

            return true
        }
    }

    private func longestStreak(in orderedDays: [Date]) -> Int {
        guard !orderedDays.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for index in 1..<orderedDays.count {
            let previous = orderedDays[index - 1]
            let day = orderedDays[index]
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }

        return longest
    }

    private func currentStreak(in orderedDays: [Date]) -> Int {
        guard let lastDay = orderedDays.last else { return 0 }

        var streak = 1
        var cursor = lastDay
        for day in orderedDays.dropLast().reversed() {
            let gap = calendar.dateComponents([.day], from: day, to: cursor).day ?? 0
            guard gap == 1 else { break }
            streak += 1
            cursor = day
        }
        return streak
    }
}

struct TrainingReviewOverview {
    let workoutCount: Int
    let setCount: Int
    let activeDays: Int
    let averageWorkoutsPerWeek: Double
    let longestWorkoutDayStreak: Int
    let currentWorkoutDayStreak: Int

    static let empty = TrainingReviewOverview(
        workoutCount: 0,
        setCount: 0,
        activeDays: 0,
        averageWorkoutsPerWeek: 0,
        longestWorkoutDayStreak: 0,
        currentWorkoutDayStreak: 0
    )
}

struct TrainingReviewMuscleGroupOption: Identifiable, Hashable {
    let id: PersistentIdentifier
    let name: String
    let colorHex: String
}

struct TrainingReviewExerciseOption: Identifiable, Hashable {
    let id: PersistentIdentifier
    let name: String
    let muscleGroupName: String
}

struct TrainingDaySummary: Identifiable {
    let date: Date
    let workouts: [Workout]
    let workoutCount: Int
    let setCount: Int
    let exerciseCount: Int
    let totalVolume: Double
    let accentColorHexes: [String]
    let exerciseSummaries: [TrainingDayExerciseSummary]

    var id: Date { date }
}

struct TrainingDayExerciseSummary: Identifiable {
    let exercise: Exercise?
    let exerciseName: String
    let muscleGroupName: String
    let colorHex: String
    let setCount: Int
    let workoutCount: Int

    var id: String {
        if let exercise {
            return "exercise-\(exercise.persistentModelID)"
        }

        return "snapshot-\(muscleGroupName)-\(exerciseName)"
    }
}

struct TrainingMonthDay: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let summary: TrainingDaySummary?

    var id: Date { date }
}
