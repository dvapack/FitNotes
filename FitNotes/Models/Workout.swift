import Foundation
import SwiftData

@Model
final class Workout {
    var date: Date
    var startedAt: Date
    var finishedAt: Date?
    var commentRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workout)
    var sets: [WorkoutSet]

    var isInProgress: Bool {
        finishedAt == nil
    }

    var comment: String {
        get { commentRaw ?? "" }
        set { commentRaw = newValue }
    }

    var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    init(date: Date = .now, startedAt: Date = .now, finishedAt: Date? = nil, comment: String = "") {
        self.date = date
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.commentRaw = comment
        self.sets = []
    }
}
