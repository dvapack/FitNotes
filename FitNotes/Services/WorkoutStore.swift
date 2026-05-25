import Foundation
import SwiftData

enum WorkoutStoreError: LocalizedError, Equatable {
    case invalidWeight
    case invalidReps
    case workoutAlreadyFinished

    var errorDescription: String? {
        switch self {
        case .invalidWeight:
            return "Weight must be greater than zero."
        case .invalidReps:
            return "Reps must be greater than zero."
        case .workoutAlreadyFinished:
            return "Finished workouts can no longer be edited."
        }
    }
}

protocol WorkoutStore {
    func createOrResumeDraftWorkout() throws -> Workout
    func fetchActiveDraftWorkout() throws -> Workout?
    func finishWorkout(_ workout: Workout, finishedAt: Date?) throws
    func updateWorkout(_ workout: Workout, date: Date, startedAt: Date, finishedAt: Date?, comment: String) throws
    func deleteWorkout(_ workout: Workout) throws
    func deleteSet(_ workoutSet: WorkoutSet) throws
    func updateSet(_ workoutSet: WorkoutSet, weight: Double, reps: Int, comment: String, isCompleted: Bool) throws
    func toggleSetCompletion(_ workoutSet: WorkoutSet) throws
    func moveSets(in workout: Workout, exercise: Exercise, fromOffsets: IndexSet, toOffset: Int) throws
    func reorderExerciseGroups(in workout: Workout, orderedExerciseIDs: [PersistentIdentifier]) throws
    func fetchWorkoutHistory() throws -> [Workout]
    func fetchWorkout(id: PersistentIdentifier) throws -> Workout?
    func addSet(to workout: Workout, exercise: Exercise, weight: Double, reps: Int, comment: String, isCompleted: Bool) throws -> WorkoutSet
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

    func finishWorkout(_ workout: Workout, finishedAt: Date? = nil) throws {
        let finalFinishedAt = finishedAt ?? Date()
        workout.finishedAt = finalFinishedAt
        if workout.date > finalFinishedAt {
            workout.date = finalFinishedAt
        }
        if workout.startedAt > finalFinishedAt {
            workout.startedAt = finalFinishedAt
        }
        try context.save()
    }

    func updateWorkout(_ workout: Workout, date: Date, startedAt: Date, finishedAt: Date?, comment: String) throws {
        let normalizedFinishedAt: Date?
        let normalizedStartedAt: Date

        if let finishedAt, startedAt > finishedAt {
            normalizedFinishedAt = finishedAt
            normalizedStartedAt = finishedAt
        } else {
            normalizedFinishedAt = finishedAt
            normalizedStartedAt = startedAt
        }

        let normalizedDate: Date
        if date > normalizedStartedAt {
            normalizedDate = normalizedStartedAt
        } else if let normalizedFinishedAt, date > normalizedFinishedAt {
            normalizedDate = normalizedFinishedAt
        } else {
            normalizedDate = date
        }

        workout.date = normalizedDate
        workout.startedAt = normalizedStartedAt
        workout.finishedAt = normalizedFinishedAt
        workout.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    func deleteWorkout(_ workout: Workout) throws {
        context.delete(workout)
        try context.save()
    }

    func deleteSet(_ workoutSet: WorkoutSet) throws {
        try ensureWorkoutIsEditable(for: workoutSet)
        let workout = workoutSet.workout
        let exercise = workoutSet.exercise
        context.delete(workoutSet)
        try context.save()
        try normalizeSetOrdersIfNeeded(for: workout, exercise: exercise)
    }

    func updateSet(_ workoutSet: WorkoutSet, weight: Double, reps: Int, comment: String, isCompleted: Bool) throws {
        try ensureWorkoutIsEditable(for: workoutSet)

        guard weight > 0 else {
            throw WorkoutStoreError.invalidWeight
        }

        guard reps > 0 else {
            throw WorkoutStoreError.invalidReps
        }

        workoutSet.weight = weight
        workoutSet.reps = reps
        workoutSet.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        workoutSet.isCompleted = isCompleted
        try context.save()
    }

    func toggleSetCompletion(_ workoutSet: WorkoutSet) throws {
        try ensureWorkoutIsEditable(for: workoutSet)
        workoutSet.isCompleted.toggle()
        try context.save()
    }

    func moveSets(in workout: Workout, exercise: Exercise, fromOffsets: IndexSet, toOffset: Int) throws {
        guard workout.isInProgress else {
            throw WorkoutStoreError.workoutAlreadyFinished
        }

        var sets = try fetchSets(for: workout, exercise: exercise)
        moveItems(in: &sets, fromOffsets: fromOffsets, toOffset: toOffset)

        for (index, set) in sets.enumerated() {
            set.setOrder = index + 1
        }

        try context.save()
    }

    func reorderExerciseGroups(in workout: Workout, orderedExerciseIDs: [PersistentIdentifier]) throws {
        guard workout.isInProgress else {
            throw WorkoutStoreError.workoutAlreadyFinished
        }

        let sets = try fetchSets(for: workout)
        let groupedSets = Dictionary(grouping: sets) { $0.exercise?.persistentModelID }

        for (index, exerciseID) in orderedExerciseIDs.enumerated() {
            let newOrder = index + 1
            groupedSets[exerciseID]?.forEach { $0.exerciseOrder = newOrder }
        }

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

    func addSet(
        to workout: Workout,
        exercise: Exercise,
        weight: Double,
        reps: Int,
        comment: String = "",
        isCompleted: Bool = false
    ) throws -> WorkoutSet {
        guard weight > 0 else {
            throw WorkoutStoreError.invalidWeight
        }

        guard reps > 0 else {
            throw WorkoutStoreError.invalidReps
        }

        guard workout.isInProgress else {
            throw WorkoutStoreError.workoutAlreadyFinished
        }

        let existingSets = try fetchSets(for: workout, exercise: exercise)
        let nextSetOrder = (existingSets.map(\.setOrder).max() ?? 0) + 1
        let exerciseOrder: Int
        if let existingOrder = existingSets.first?.exerciseOrder {
            exerciseOrder = existingOrder
        } else {
            exerciseOrder = try nextExerciseOrder(in: workout) + 1
        }
        let workoutSet = WorkoutSet(
            exerciseOrder: exerciseOrder,
            setOrder: nextSetOrder,
            weight: weight,
            reps: reps,
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
            isCompleted: isCompleted,
            exerciseNameSnapshot: exercise.name,
            muscleGroupNameSnapshot: exercise.muscleGroup?.name ?? "Uncategorized",
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
            sortBy: [SortDescriptor(\.exerciseOrder), SortDescriptor(\.setOrder)]
        ))
    }

    private func nextExerciseOrder(in workout: Workout) throws -> Int {
        let sets = try fetchSets(for: workout)
        return sets.map(\.exerciseOrder).max() ?? 0
    }

    private func normalizeSetOrdersIfNeeded(for workout: Workout?, exercise: Exercise?) throws {
        guard let workout, let exercise else {
            return
        }

        let remainingSets = try fetchSets(for: workout, exercise: exercise)
        for (index, set) in remainingSets.enumerated() {
            set.setOrder = index + 1
        }
        try context.save()
    }

    private func ensureWorkoutIsEditable(for workoutSet: WorkoutSet) throws {
        guard workoutSet.workout?.isInProgress != false else {
            throw WorkoutStoreError.workoutAlreadyFinished
        }
    }

    private func moveItems<T>(in items: inout [T], fromOffsets: IndexSet, toOffset: Int) {
        let movingItems = fromOffsets.map { items[$0] }
        for index in fromOffsets.sorted(by: >) {
            items.remove(at: index)
        }
        items.insert(contentsOf: movingItems, at: min(toOffset, items.count))
    }
}
