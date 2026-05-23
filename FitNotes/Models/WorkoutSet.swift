import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var exerciseOrder: Int
    var setOrder: Int
    var weight: Double
    var reps: Int
    var commentRaw: String?
    var isCompleted: Bool
    var exerciseNameSnapshot: String?
    var muscleGroupNameSnapshot: String?

    var workout: Workout?
    var exercise: Exercise?

    var comment: String {
        get { commentRaw ?? "" }
        set { commentRaw = newValue }
    }

    init(
        exerciseOrder: Int = 0,
        setOrder: Int,
        weight: Double,
        reps: Int,
        comment: String = "",
        isCompleted: Bool = false,
        exerciseNameSnapshot: String = "",
        muscleGroupNameSnapshot: String = "",
        workout: Workout? = nil,
        exercise: Exercise? = nil
    ) {
        self.exerciseOrder = exerciseOrder
        self.setOrder = setOrder
        self.weight = weight
        self.reps = reps
        self.commentRaw = comment
        self.isCompleted = isCompleted
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.muscleGroupNameSnapshot = muscleGroupNameSnapshot
        self.workout = workout
        self.exercise = exercise
    }
}
