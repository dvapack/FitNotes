import Foundation
import SwiftData

struct RoutineExerciseDraft: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var weight: Double
    var reps: Int
    var setCount: Int
    var supersetGroup: String?
}

enum RoutineStoreError: LocalizedError, Equatable {
    case emptyRoutineName
    case emptyDayName
    case invalidTemplateSet

    var errorDescription: String? {
        switch self {
        case .emptyRoutineName:
            return "Routine name must not be empty."
        case .emptyDayName:
            return "Routine day name must not be empty."
        case .invalidTemplateSet:
            return "Routine template sets need weight, reps, and set count greater than zero."
        }
    }
}

@MainActor
struct RoutineStore {
    private let context: ModelContext
    private let workoutStore: DefaultWorkoutStore

    init(context: ModelContext) {
        self.context = context
        self.workoutStore = DefaultWorkoutStore(context: context)
    }

    func fetchRoutines() throws -> [Routine] {
        try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.name)]))
    }

    @discardableResult
    func createRoutine(name: String, notes: String, dayName: String, exercises: [RoutineExerciseDraft]) throws -> Routine {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDayName = dayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw RoutineStoreError.emptyRoutineName
        }

        guard !trimmedDayName.isEmpty else {
            throw RoutineStoreError.emptyDayName
        }

        let routine = Routine(name: trimmedName, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        let day = RoutineDay(name: trimmedDayName, sortOrder: 0, routine: routine)

        context.insert(routine)
        context.insert(day)

        for (exerciseIndex, draft) in exercises.enumerated() {
            guard draft.weight > 0, draft.reps > 0, draft.setCount > 0 else {
                throw RoutineStoreError.invalidTemplateSet
            }

            let routineExercise = RoutineExercise(
                sortOrder: exerciseIndex,
                supersetGroup: draft.supersetGroup,
                day: day,
                exercise: draft.exercise
            )
            context.insert(routineExercise)

            for setIndex in 0..<draft.setCount {
                let templateSet = RoutineTemplateSet(
                    setOrder: setIndex + 1,
                    weight: draft.weight,
                    reps: draft.reps,
                    routineExercise: routineExercise
                )
                context.insert(templateSet)
            }
        }

        try context.save()
        return routine
    }

    func deleteRoutine(_ routine: Routine) throws {
        context.delete(routine)
        try context.save()
    }

    @discardableResult
    func startRoutine(_ routine: Routine) throws -> Workout {
        let workout = try workoutStore.createOrResumeDraftWorkout()
        let orderedDays = routine.days.sorted { $0.sortOrder < $1.sortOrder }

        for day in orderedDays {
            let orderedExercises = day.exercises.sorted { $0.sortOrder < $1.sortOrder }
            for routineExercise in orderedExercises {
                guard let exercise = routineExercise.exercise else { continue }
                let orderedSets = routineExercise.templateSets.sorted { $0.setOrder < $1.setOrder }
                for templateSet in orderedSets {
                    _ = try workoutStore.addSet(
                        to: workout,
                        exercise: exercise,
                        weight: templateSet.weight,
                        reps: templateSet.reps,
                        comment: templateSet.note,
                        isCompleted: true
                    )
                }
            }
        }

        workout.comment = workout.comment.isEmpty ? "Routine: \(routine.name)" : workout.comment
        try context.save()
        return workout
    }
}
