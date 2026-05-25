import Foundation
import SwiftData

@MainActor
struct LegacyDataBackfillService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func backfillIfNeeded() throws -> Int {
        var updatedRecordCount = 0

        updatedRecordCount += try backfillSettings()
        updatedRecordCount += try backfillBodyMeasurements()
        if try backfillMuscleGroups() {
            updatedRecordCount += 1
        }
        updatedRecordCount += try backfillExercises()
        updatedRecordCount += try backfillWorkouts()
        updatedRecordCount += try backfillWorkoutSets()

        if updatedRecordCount > 0 {
            try context.save()
        }

        return updatedRecordCount
    }

    private func backfillSettings() throws -> Int {
        let settingsStore = AppSettingsStore(context: context)
        let settings = try settingsStore.fetchSettings()

        guard let primarySettings = settings.first else {
            context.insert(AppSettings())
            return 1
        }

        var changedCount = 0

        for duplicate in settings.dropFirst() {
            context.delete(duplicate)
            changedCount += 1
        }

        if AppUnitSystem(rawValue: primarySettings.unitSystemRaw) == nil {
            primarySettings.unitSystemRaw = AppUnitSystem.kilograms.rawValue
            changedCount += 1
        }

        if primarySettings.weightIncrement <= 0 {
            primarySettings.weightIncrement = 2.5
            changedCount += 1
        }

        if CalendarWeekStart(rawValue: primarySettings.calendarWeekStartRaw) == nil {
            primarySettings.calendarWeekStartRaw = CalendarWeekStart.monday.rawValue
            changedCount += 1
        }

        if PersonalRecordBehavior(rawValue: primarySettings.personalRecordBehaviorRaw) == nil {
            primarySettings.personalRecordBehaviorRaw = PersonalRecordBehavior.includeEstimatedOneRepMax.rawValue
            changedCount += 1
        }

        if SetCompletionBehavior(rawValue: primarySettings.setCompletionBehaviorRaw) == nil {
            primarySettings.setCompletionBehaviorRaw = SetCompletionBehavior.markCompleted.rawValue
            changedCount += 1
        }

        if NextSetBehavior(rawValue: primarySettings.nextSetBehaviorRaw) == nil {
            primarySettings.nextSetBehaviorRaw = NextSetBehavior.repeatPreviousValues.rawValue
            changedCount += 1
        }

        return changedCount
    }

    private func backfillMuscleGroups() throws -> Bool {
        let groups = try context.fetch(FetchDescriptor<MuscleGroup>())
        var changed = false

        for group in groups where group.colorHex?.isEmpty != false {
            group.colorHex = "#4F7A28"
            changed = true
        }

        return changed
    }

    private func backfillBodyMeasurements() throws -> Int {
        let metrics = try context.fetch(FetchDescriptor<BodyMeasurementMetric>())
        var changedCount = 0

        for metric in metrics {
            var changed = false

            let normalizedName = metric.name.normalizedCatalogName
            if metric.normalizedName != normalizedName {
                metric.normalizedName = normalizedName
                changed = true
            }

            let trimmedUnit = metric.unitSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedUnit.isEmpty {
                metric.unitSymbol = "unit"
                changed = true
            } else if metric.unitSymbol != trimmedUnit {
                metric.unitSymbol = trimmedUnit
                changed = true
            }

            if let goalDirectionRaw = metric.goalDirectionRaw,
               BodyMeasurementGoalDirection(rawValue: goalDirectionRaw) == nil {
                metric.goalDirectionRaw = nil
                metric.goalTargetValue = nil
                changed = true
            }

            if let goalTargetValue = metric.goalTargetValue, goalTargetValue <= 0 {
                metric.goalTargetValue = nil
                metric.goalDirectionRaw = nil
                changed = true
            }

            if metric.goalNotesRaw == nil {
                metric.goalNotesRaw = ""
                changed = true
            }

            if changed {
                changedCount += 1
            }
        }

        let entries = try context.fetch(FetchDescriptor<BodyMeasurementEntry>())
        for entry in entries where entry.noteRaw == nil {
            entry.noteRaw = ""
            changedCount += 1
        }

        return changedCount
    }

    private func backfillExercises() throws -> Int {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var changedCount = 0

        for exercise in exercises {
            var changed = false

            let normalizedName = exercise.name.normalizedExerciseName
            if exercise.normalizedName != normalizedName {
                exercise.normalizedName = normalizedName
                changed = true
            }

            if exercise.notesRaw == nil {
                exercise.notesRaw = ""
                changed = true
            }

            if ExerciseType(rawValue: exercise.exerciseTypeRaw ?? "") == nil {
                exercise.exerciseTypeRaw = ExerciseType.weightReps.rawValue
                changed = true
            }

            if WeightUnit(rawValue: exercise.preferredWeightUnitRaw ?? "") == nil {
                exercise.preferredWeightUnitRaw = WeightUnit.kg.rawValue
                changed = true
            }

            if exercise.defaultRestSeconds < 0 {
                exercise.defaultRestSeconds = 90
                changed = true
            }

            if ExerciseProgressionView(rawValue: exercise.defaultProgressionViewRaw ?? "") == nil {
                exercise.defaultProgressionViewRaw = ExerciseProgressionView.maxWeight.rawValue
                changed = true
            }

            if let goalMetricRaw = exercise.goalMetricRaw,
               ExerciseProgressionView(rawValue: goalMetricRaw) == nil {
                exercise.goalMetricRaw = nil
                exercise.goalTargetValue = nil
                changed = true
            }

            if let goalTargetValue = exercise.goalTargetValue, goalTargetValue <= 0 {
                exercise.goalTargetValue = nil
                exercise.goalMetricRaw = nil
                changed = true
            }

            if exercise.goalNotesRaw == nil {
                exercise.goalNotesRaw = ""
                changed = true
            }

            if changed {
                changedCount += 1
            }
        }

        return changedCount
    }

    private func backfillWorkouts() throws -> Int {
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        var changedCount = 0

        for workout in workouts {
            var changed = false

            if workout.commentRaw == nil {
                workout.commentRaw = ""
                changed = true
            }

            if workout.startedAt > workout.date {
                workout.date = workout.startedAt
                changed = true
            }

            if let finishedAt = workout.finishedAt {
                if workout.date > finishedAt {
                    workout.date = finishedAt
                    changed = true
                }

                if workout.startedAt > finishedAt {
                    workout.startedAt = finishedAt
                    changed = true
                }
            }

            if changed {
                changedCount += 1
            }
        }

        return changedCount
    }

    private func backfillWorkoutSets() throws -> Int {
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        var changedCount = 0

        for workout in Set(sets.compactMap(\.workout)) {
            let groupedByExercise = Dictionary(grouping: workout.sets) { $0.exercise?.persistentModelID }
            let orderedExerciseIDs = groupedByExercise.keys.sorted { lhs, rhs in
                let lhsOrder = groupedByExercise[lhs]?.map(\.exerciseOrder).filter { $0 > 0 }.min() ?? Int.max
                let rhsOrder = groupedByExercise[rhs]?.map(\.exerciseOrder).filter { $0 > 0 }.min() ?? Int.max

                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }

                let lhsName = groupedByExercise[lhs]?.first?.exerciseNameSnapshot ?? groupedByExercise[lhs]?.first?.exercise?.name ?? ""
                let rhsName = groupedByExercise[rhs]?.first?.exerciseNameSnapshot ?? groupedByExercise[rhs]?.first?.exercise?.name ?? ""
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

            let exerciseOrderByID = Dictionary(uniqueKeysWithValues: orderedExerciseIDs.enumerated().map { index, exerciseID in
                (exerciseID, index + 1)
            })

            for exerciseID in orderedExerciseIDs {
                let orderedSets = (groupedByExercise[exerciseID] ?? []).sorted {
                    if $0.setOrder != $1.setOrder {
                        return $0.setOrder < $1.setOrder
                    }

                    return $0.weight < $1.weight
                }

                for (index, set) in orderedSets.enumerated() {
                    var changed = false

                    if set.commentRaw == nil {
                        set.commentRaw = ""
                        changed = true
                    }

                    if set.exerciseNameSnapshot?.isEmpty != false {
                        set.exerciseNameSnapshot = set.exercise?.name ?? ""
                        changed = true
                    }

                    if set.muscleGroupNameSnapshot?.isEmpty != false {
                        set.muscleGroupNameSnapshot = set.exercise?.muscleGroup?.name ?? ""
                        changed = true
                    }

                    let expectedSetOrder = index + 1
                    if set.setOrder != expectedSetOrder {
                        set.setOrder = expectedSetOrder
                        changed = true
                    }

                    let expectedExerciseOrder = exerciseOrderByID[exerciseID] ?? 0
                    if set.exerciseOrder != expectedExerciseOrder {
                        set.exerciseOrder = expectedExerciseOrder
                        changed = true
                    }

                    if changed {
                        changedCount += 1
                    }
                }
            }
        }

        return changedCount
    }
}
