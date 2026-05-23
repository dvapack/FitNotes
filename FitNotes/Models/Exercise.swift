import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String
    var normalizedName: String
    var isCustom: Bool
    var createdAt: Date

    var muscleGroup: MuscleGroup?

    @Relationship(deleteRule: .nullify, inverse: \WorkoutSet.exercise)
    var workoutSets: [WorkoutSet]

    init(name: String, normalizedName: String, isCustom: Bool, createdAt: Date = .now, muscleGroup: MuscleGroup? = nil) {
        self.name = name
        self.normalizedName = normalizedName
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.muscleGroup = muscleGroup
        self.workoutSets = []
    }
}
