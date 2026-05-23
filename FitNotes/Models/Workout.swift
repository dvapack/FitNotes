import Foundation
import SwiftData

@Model
final class Workout {
    var date: Date
    var startedAt: Date
    var finishedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workout)
    var sets: [WorkoutSet]

    var isInProgress: Bool {
        finishedAt == nil
    }

    init(date: Date = .now, startedAt: Date = .now, finishedAt: Date? = nil) {
        self.date = date
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sets = []
    }
}
