import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([
        MuscleGroup.self,
        Exercise.self,
        Workout.self,
        WorkoutSet.self,
    ])

    static func makeSharedContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create shared model container: \(error)")
        }
    }

    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory model container: \(error)")
        }
    }
}
