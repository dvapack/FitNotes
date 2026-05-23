import Foundation
import SwiftData

@Model
final class MuscleGroup {
    var name: String
    var sortOrder: Int
    var colorHex: String?

    @Relationship(deleteRule: .cascade, inverse: \Exercise.muscleGroup)
    var exercises: [Exercise]

    init(name: String, sortOrder: Int, colorHex: String = "#4F7A28") {
        self.name = name
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.exercises = []
    }
}
