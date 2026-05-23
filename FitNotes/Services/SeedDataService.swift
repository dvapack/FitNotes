import Foundation
import SwiftData

@MainActor
struct SeedDataService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func seedIfNeeded() throws {
        let descriptor = FetchDescriptor<MuscleGroup>()
        let existingGroups = try context.fetch(descriptor)
        guard existingGroups.isEmpty else {
            return
        }

        for (index, seed) in SeedCatalog.defaultGroups.enumerated() {
            let group = MuscleGroup(name: seed.name, sortOrder: index)
            context.insert(group)

            for exerciseName in seed.exercises {
                let exercise = Exercise(
                    name: exerciseName,
                    normalizedName: exerciseName.normalizedExerciseName,
                    isCustom: false,
                    muscleGroup: group
                )
                context.insert(exercise)
            }
        }

        try context.save()
    }
}

enum SeedCatalog {
    static let defaultGroups: [(name: String, exercises: [String])] = [
        ("Chest", ["Bench Press", "Push-Up", "Dumbbell Fly"]),
        ("Back", ["Deadlift", "Pull-Up", "Barbell Row"]),
        ("Shoulders", ["Overhead Press", "Lateral Raise", "Seated Dumbbell Press"]),
        ("Biceps", ["Barbell Curl", "Hammer Curl", "Incline Dumbbell Curl"]),
        ("Triceps", ["Skull Crusher", "Cable Pushdown", "Dips"]),
        ("Legs", ["Back Squat", "Lunge", "Leg Press"]),
        ("Abs", ["Plank", "Hanging Knee Raise", "Cable Crunch"]),
    ]
}
