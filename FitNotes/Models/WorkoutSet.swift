import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var setOrder: Int
    var weight: Double
    var reps: Int

    var workout: Workout?
    var exercise: Exercise?

    init(setOrder: Int, weight: Double, reps: Int, workout: Workout? = nil, exercise: Exercise? = nil) {
        self.setOrder = setOrder
        self.weight = weight
        self.reps = reps
        self.workout = workout
        self.exercise = exercise
    }
}
