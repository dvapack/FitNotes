import Foundation
import SwiftData

enum WorkoutStoreError: LocalizedError {
    case invalidWeight
    case invalidReps

    var errorDescription: String? {
        switch self {
        case .invalidWeight:
            return "Weight must be greater than zero."
        case .invalidReps:
            return "Reps must be greater than zero."
        }
    }
}

protocol WorkoutStore {
    func createOrResumeDraftWorkout() throws -> Workout
    func fetchActiveDraftWorkout() throws -> Workout?
    func finishWorkout(_ workout: Workout) throws
    func deleteWorkout(_ workout: Workout) throws
    func deleteSet(_ workoutSet: WorkoutSet) throws
    func fetchWorkoutHistory() throws -> [Workout]
    func fetchWorkout(id: PersistentIdentifier) throws -> Workout?
    func addSet(to workout: Workout, exercise: Exercise, weight: Double, reps: Int) throws -> WorkoutSet
    func fetchSets(for workout: Workout, exercise: Exercise) throws -> [WorkoutSet]
    func fetchSets(for workout: Workout) throws -> [WorkoutSet]
}

@MainActor
struct DefaultWorkoutStore: WorkoutStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func createOrResumeDraftWorkout() throws -> Workout {
        if let draft = try fetchActiveDraftWorkout() {
            return draft
        }

        let now = Date()
        let workout = Workout(date: now, startedAt: now)
        context.insert(workout)
        try context.save()
        return workout
    }

    func fetchActiveDraftWorkout() throws -> Workout? {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.finishedAt == nil
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func finishWorkout(_ workout: Workout) throws {
        workout.finishedAt = Date()
        if workout.date > workout.finishedAt ?? workout.date {
            workout.date = workout.finishedAt ?? workout.date
        }
        try context.save()
    }

    func deleteWorkout(_ workout: Workout) throws {
        context.delete(workout)
        try context.save()
    }

    func deleteSet(_ workoutSet: WorkoutSet) throws {
        context.delete(workoutSet)
        try context.save()
    }

    func fetchWorkoutHistory() throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.finishedAt != nil
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchWorkout(id: PersistentIdentifier) throws -> Workout? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.persistentModelID == id
            }
        )
        return try context.fetch(descriptor).first
    }

    func addSet(to workout: Workout, exercise: Exercise, weight: Double, reps: Int) throws -> WorkoutSet {
        guard weight > 0 else {
            throw WorkoutStoreError.invalidWeight
        }

        guard reps > 0 else {
            throw WorkoutStoreError.invalidReps
        }

        let workoutID = workout.persistentModelID
        let exerciseID = exercise.persistentModelID

        let existingSets = try context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> { set in
                set.workout?.persistentModelID == workoutID &&
                set.exercise?.persistentModelID == exerciseID
            },
            sortBy: [SortDescriptor(\.setOrder, order: .reverse)]
        ))

        let nextSetOrder = (existingSets.first?.setOrder ?? 0) + 1
        let workoutSet = WorkoutSet(
            setOrder: nextSetOrder,
            weight: weight,
            reps: reps,
            workout: workout,
            exercise: exercise
        )

        context.insert(workoutSet)
        try context.save()
        return workoutSet
    }

    func fetchSets(for workout: Workout, exercise: Exercise) throws -> [WorkoutSet] {
        let workoutID = workout.persistentModelID
        let exerciseID = exercise.persistentModelID

        return try context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> { set in
                set.workout?.persistentModelID == workoutID &&
                set.exercise?.persistentModelID == exerciseID
            },
            sortBy: [SortDescriptor(\.setOrder)]
        ))
    }

    func fetchSets(for workout: Workout) throws -> [WorkoutSet] {
        let workoutID = workout.persistentModelID

        return try context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> { set in
                set.workout?.persistentModelID == workoutID
            },
            sortBy: [SortDescriptor(\.setOrder)]
        ))
    }
}
