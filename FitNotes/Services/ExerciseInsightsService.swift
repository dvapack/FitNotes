import Foundation
import SwiftData

@MainActor
struct ExerciseInsightsService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func makeSnapshot() throws -> WorkoutStatisticsSnapshot {
        let workouts = try context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.finishedAt != nil
            },
            sortBy: [SortDescriptor(\.startedAt)]
        ))

        return WorkoutStatisticsSnapshot(workouts: workouts)
    }

    func history(for exercise: Exercise) -> [WorkoutSet] {
        exercise.workoutSets
            .filter { $0.workout?.finishedAt != nil }
            .sorted {
                ($0.workout?.date ?? .distantPast) > ($1.workout?.date ?? .distantPast)
            }
    }
}
