import Foundation
import SwiftData

@Model
final class MuscleGroup {
    var name: String
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \Exercise.muscleGroup)
    var exercises: [Exercise]

    init(name: String, sortOrder: Int) {
        self.name = name
        self.sortOrder = sortOrder
        self.exercises = []
    }
}
