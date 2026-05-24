import Foundation
import SwiftData

enum ExerciseStoreError: LocalizedError, Equatable {
    case emptyExerciseName
    case emptyMuscleGroupName
    case invalidRestTimer
    case duplicateMuscleGroup
    case duplicateExercise

    var errorDescription: String? {
        switch self {
        case .emptyExerciseName:
            return "Exercise names must not be empty."
        case .emptyMuscleGroupName:
            return "Muscle group names must not be empty."
        case .invalidRestTimer:
            return "Default rest time must be zero or greater."
        case .duplicateMuscleGroup:
            return "A muscle group with that name already exists."
        case .duplicateExercise:
            return "An exercise with that name already exists in this muscle group."
        }
    }
}

protocol ExerciseStore {
    func fetchMuscleGroups() throws -> [MuscleGroup]
    func fetchExercises(for muscleGroup: MuscleGroup) throws -> [Exercise]
    func searchExercises(query: String, favoritesOnly: Bool) throws -> [Exercise]
    func createMuscleGroup(name: String) throws -> MuscleGroup
    func updateMuscleGroup(_ muscleGroup: MuscleGroup, name: String, colorHex: String) throws
    func deleteMuscleGroup(_ muscleGroup: MuscleGroup) throws
    func moveMuscleGroups(fromOffsets: IndexSet, toOffset: Int) throws
    func createExercise(
        name: String,
        in muscleGroup: MuscleGroup,
        isCustom: Bool,
        notes: String,
        isFavorite: Bool,
        exerciseType: ExerciseType,
        preferredWeightUnit: WeightUnit,
        defaultRestSeconds: Int
    ) throws -> Exercise
    func updateExercise(
        _ exercise: Exercise,
        name: String,
        muscleGroup: MuscleGroup,
        notes: String,
        isFavorite: Bool,
        exerciseType: ExerciseType,
        preferredWeightUnit: WeightUnit,
        defaultRestSeconds: Int,
        defaultProgressionView: ExerciseProgressionView
    ) throws
    func toggleFavorite(_ exercise: Exercise) throws
    func deleteExercise(_ exercise: Exercise) throws
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
        return sortedExercises(try context.fetch(descriptor))
    }

    func searchExercises(query: String, favoritesOnly: Bool = false) throws -> [Exercise] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var exercises = try sortedExercises(context.fetch(FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.name)]
        )))

        if favoritesOnly {
            exercises = exercises.filter { $0.isFavorite }
        }

        guard !trimmedQuery.isEmpty else {
            return exercises
        }

        let normalizedQuery = trimmedQuery.normalizedCatalogName
        return exercises.filter { exercise in
            exercise.normalizedName.contains(normalizedQuery) ||
            exercise.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            exercise.muscleGroup?.name.localizedCaseInsensitiveContains(trimmedQuery) == true
        }
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

    func updateMuscleGroup(_ muscleGroup: MuscleGroup, name: String, colorHex: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ExerciseStoreError.emptyMuscleGroupName
        }

        let normalizedName = trimmedName.normalizedCatalogName
        let existingGroups = try fetchMuscleGroups()
        if existingGroups.contains(where: {
            $0.persistentModelID != muscleGroup.persistentModelID &&
            $0.name.normalizedCatalogName == normalizedName
        }) {
            throw ExerciseStoreError.duplicateMuscleGroup
        }

        muscleGroup.name = trimmedName
        muscleGroup.colorHex = colorHex
        try context.save()
    }

    func deleteMuscleGroup(_ muscleGroup: MuscleGroup) throws {
        context.delete(muscleGroup)
        try context.save()
    }

    func moveMuscleGroups(fromOffsets: IndexSet, toOffset: Int) throws {
        var groups = try fetchMuscleGroups()
        moveItems(in: &groups, fromOffsets: fromOffsets, toOffset: toOffset)

        for (index, group) in groups.enumerated() {
            group.sortOrder = index
        }

        try context.save()
    }

    func createExercise(
        name: String,
        in muscleGroup: MuscleGroup,
        isCustom: Bool = true,
        notes: String = "",
        isFavorite: Bool = false,
        exerciseType: ExerciseType = .weightReps,
        preferredWeightUnit: WeightUnit = .kg,
        defaultRestSeconds: Int = 90
    ) throws -> Exercise {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ExerciseStoreError.emptyExerciseName
        }

        guard defaultRestSeconds >= 0 else {
            throw ExerciseStoreError.invalidRestTimer
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
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isFavorite: isFavorite,
            exerciseType: exerciseType,
            preferredWeightUnit: preferredWeightUnit,
            defaultRestSeconds: defaultRestSeconds,
            muscleGroup: muscleGroup
        )
        context.insert(exercise)
        try context.save()
        return exercise
    }

    func updateExercise(
        _ exercise: Exercise,
        name: String,
        muscleGroup: MuscleGroup,
        notes: String,
        isFavorite: Bool,
        exerciseType: ExerciseType,
        preferredWeightUnit: WeightUnit,
        defaultRestSeconds: Int,
        defaultProgressionView: ExerciseProgressionView
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ExerciseStoreError.emptyExerciseName
        }

        guard defaultRestSeconds >= 0 else {
            throw ExerciseStoreError.invalidRestTimer
        }

        let normalizedName = trimmedName.normalizedCatalogName
        let groupID = muscleGroup.persistentModelID
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { candidate in
                candidate.normalizedName == normalizedName &&
                candidate.muscleGroup?.persistentModelID == groupID
            }
        )
        if try context.fetch(descriptor).contains(where: { $0.persistentModelID != exercise.persistentModelID }) {
            throw ExerciseStoreError.duplicateExercise
        }

        exercise.name = trimmedName
        exercise.normalizedName = normalizedName
        exercise.muscleGroup = muscleGroup
        exercise.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.isFavorite = isFavorite
        exercise.exerciseType = exerciseType
        exercise.preferredWeightUnit = preferredWeightUnit
        exercise.defaultRestSeconds = defaultRestSeconds
        exercise.defaultProgressionView = defaultProgressionView
        try context.save()
    }

    func toggleFavorite(_ exercise: Exercise) throws {
        exercise.isFavorite.toggle()
        try context.save()
    }

    func deleteExercise(_ exercise: Exercise) throws {
        context.delete(exercise)
        try context.save()
    }

    private func sortedExercises(_ exercises: [Exercise]) -> [Exercise] {
        exercises.sorted {
            if $0.isFavorite == $1.isFavorite {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            return $0.isFavorite && !$1.isFavorite
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
