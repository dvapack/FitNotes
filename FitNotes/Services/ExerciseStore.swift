import Foundation
import SwiftData

enum ExerciseStoreError: LocalizedError, Equatable {
    case emptyExerciseName
    case emptyMuscleGroupName

    var errorDescription: String? {
        switch self {
        case .emptyExerciseName:
            return "Exercise names must not be empty."
        case .emptyMuscleGroupName:
            return "Muscle group names must not be empty."
        }
    }
}

protocol ExerciseStore {
    func fetchMuscleGroups() throws -> [MuscleGroup]
    func fetchExercises(for muscleGroup: MuscleGroup) throws -> [Exercise]
    func createMuscleGroup(name: String) throws -> MuscleGroup
    func createExercise(name: String, in muscleGroup: MuscleGroup, isCustom: Bool) throws -> Exercise
}

@MainActor
struct DefaultExerciseStore: ExerciseStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchMuscleGroups() throws -> [MuscleGroup] {
        let descriptor = FetchDescriptor<MuscleGroup>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetchExercises(for muscleGroup: MuscleGroup) throws -> [Exercise] {
        let groupID = muscleGroup.persistentModelID
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.muscleGroup?.persistentModelID == groupID
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func createMuscleGroup(name: String) throws -> MuscleGroup {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ExerciseStoreError.emptyMuscleGroupName
        }

        let normalizedName = trimmedName.normalizedCatalogName
        let existingGroups = try fetchMuscleGroups()

        if let existingGroup = existingGroups.first(where: { $0.name.normalizedCatalogName == normalizedName }) {
            return existingGroup
        }

        let nextSortOrder = (existingGroups.map(\.sortOrder).max() ?? -1) + 1
        let muscleGroup = MuscleGroup(name: trimmedName, sortOrder: nextSortOrder)
        context.insert(muscleGroup)
        try context.save()
        return muscleGroup
    }

    func createExercise(name: String, in muscleGroup: MuscleGroup, isCustom: Bool = true) throws -> Exercise {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ExerciseStoreError.emptyExerciseName
        }

        let normalizedName = trimmedName.normalizedCatalogName
        let groupID = muscleGroup.persistentModelID

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.normalizedName == normalizedName &&
                exercise.muscleGroup?.persistentModelID == groupID
            }
        )

        if let existingExercise = try context.fetch(descriptor).first {
            return existingExercise
        }

        let exercise = Exercise(
            name: trimmedName,
            normalizedName: normalizedName,
            isCustom: isCustom,
            muscleGroup: muscleGroup
        )
        context.insert(exercise)
        try context.save()
        return exercise
    }
}
