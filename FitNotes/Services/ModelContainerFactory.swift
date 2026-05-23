import SwiftData
import Foundation

enum ModelContainerFactory {
    static let schema = Schema([
        MuscleGroup.self,
        Exercise.self,
        Workout.self,
        WorkoutSet.self,
        Routine.self,
        RoutineDay.self,
        RoutineExercise.self,
        RoutineTemplateSet.self,
    ])

    static func makeSharedContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            do {
                try resetDefaultStoreFiles()
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to create shared model container: \(error)")
            }
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

    private static func resetDefaultStoreFiles() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeURL = applicationSupport.appendingPathComponent("default.store")
        let sidecarExtensions = ["", "-shm", "-wal"]

        for suffix in sidecarExtensions {
            let candidateURL = suffix.isEmpty ? storeURL : applicationSupport.appendingPathComponent("default.store\(suffix)")
            if FileManager.default.fileExists(atPath: candidateURL.path()) {
                try FileManager.default.removeItem(at: candidateURL)
            }
        }
    }
}
