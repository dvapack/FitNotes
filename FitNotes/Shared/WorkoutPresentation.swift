import Foundation
import SwiftData

struct WorkoutExerciseGroup: Identifiable {
    let exercise: Exercise
    let sets: [WorkoutSet]

    var id: PersistentIdentifier {
        exercise.persistentModelID
    }

    var title: String {
        exercise.name
    }

    var muscleGroupName: String {
        exercise.muscleGroup?.name ?? "Uncategorized"
    }
}

extension Array where Element == WorkoutSet {
    func groupedByExercise() -> [WorkoutExerciseGroup] {
        let grouped = Dictionary(grouping: self) { set in
            set.exercise?.persistentModelID
        }

        return grouped.compactMap { _, sets in
            guard let exercise = sets.first?.exercise else {
                return nil
            }

            return WorkoutExerciseGroup(
                exercise: exercise,
                sets: sets.sorted { $0.setOrder < $1.setOrder }
            )
        }
        .sorted {
            if $0.muscleGroupName == $1.muscleGroupName {
                return $0.title < $1.title
            }

            return $0.muscleGroupName < $1.muscleGroupName
        }
    }
}
