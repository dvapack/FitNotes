import Foundation
import SwiftData

@Model
final class Routine {
    var name: String
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutineDay.routine)
    var days: [RoutineDay]

    init(name: String, notes: String = "", createdAt: Date = .now) {
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.days = []
    }
}

@Model
final class RoutineDay {
    var name: String
    var sortOrder: Int

    var routine: Routine?

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.day)
    var exercises: [RoutineExercise]

    init(name: String, sortOrder: Int, routine: Routine? = nil) {
        self.name = name
        self.sortOrder = sortOrder
        self.routine = routine
        self.exercises = []
    }
}

@Model
final class RoutineExercise {
    var sortOrder: Int
    var supersetGroup: String?

    var day: RoutineDay?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \RoutineTemplateSet.routineExercise)
    var templateSets: [RoutineTemplateSet]

    init(sortOrder: Int, supersetGroup: String? = nil, day: RoutineDay? = nil, exercise: Exercise? = nil) {
        self.sortOrder = sortOrder
        self.supersetGroup = supersetGroup
        self.day = day
        self.exercise = exercise
        self.templateSets = []
    }
}

@Model
final class RoutineTemplateSet {
    var setOrder: Int
    var weight: Double
    var reps: Int
    var note: String

    var routineExercise: RoutineExercise?

    init(setOrder: Int, weight: Double, reps: Int, note: String = "", routineExercise: RoutineExercise? = nil) {
        self.setOrder = setOrder
        self.weight = weight
        self.reps = reps
        self.note = note
        self.routineExercise = routineExercise
    }
}
