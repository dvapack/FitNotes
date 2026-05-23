import Foundation
import SwiftData

struct WorkoutExerciseGroup: Identifiable {
    let exercise: Exercise?
    let sets: [WorkoutSet]
    let exerciseOrder: Int

    var id: String {
        if let exercise {
            return "exercise-\(exercise.persistentModelID)"
        }

        let snapshotName = sets.first?.exerciseNameSnapshot ?? "deleted"
        return "snapshot-\(snapshotName)-\(exerciseOrder)"
    }

    var title: String {
        exercise?.name ?? sets.first?.exerciseNameSnapshot ?? "Deleted Exercise"
    }

    var muscleGroupName: String {
        exercise?.muscleGroup?.name ?? sets.first?.muscleGroupNameSnapshot ?? "Uncategorized"
    }
}

extension Array where Element == WorkoutSet {
    func groupedByExercise() -> [WorkoutExerciseGroup] {
        let grouped = Dictionary(grouping: self) { set in
            set.exercise?.persistentModelID
        }

        return grouped.compactMap { _, sets in
            return WorkoutExerciseGroup(
                exercise: sets.first?.exercise,
                sets: sets.sorted { lhs, rhs in
                    return lhs.setOrder < rhs.setOrder
                },
                exerciseOrder: sets.map(\.exerciseOrder).min() ?? 0
            )
        }
        .sorted {
            if $0.exerciseOrder == $1.exerciseOrder {
                if $0.muscleGroupName == $1.muscleGroupName {
                    return $0.title < $1.title
                }

                return $0.muscleGroupName < $1.muscleGroupName
            }

            return $0.exerciseOrder < $1.exerciseOrder
        }
    }
}
