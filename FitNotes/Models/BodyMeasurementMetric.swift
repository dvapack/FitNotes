import Foundation
import SwiftData

enum BodyMeasurementGoalDirection: String, Codable, CaseIterable, Identifiable {
    case decrease
    case increase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decrease:
            return "Decrease"
        case .increase:
            return "Increase"
        }
    }
}

@Model
final class BodyMeasurementMetric {
    var name: String
    var normalizedName: String
    var unitSymbol: String
    var isEnabled: Bool
    var sortOrder: Int
    var createdAt: Date
    var goalDirectionRaw: String?
    var goalTargetValue: Double?
    var goalNotesRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \BodyMeasurementEntry.metric)
    var entries: [BodyMeasurementEntry]

    var goalDirection: BodyMeasurementGoalDirection? {
        get {
            guard let goalDirectionRaw else { return nil }
            return BodyMeasurementGoalDirection(rawValue: goalDirectionRaw)
        }
        set { goalDirectionRaw = newValue?.rawValue }
    }

    var goalNotes: String {
        get { goalNotesRaw ?? "" }
        set { goalNotesRaw = newValue }
    }

    var hasGoal: Bool {
        goalDirection != nil && (goalTargetValue ?? 0) > 0
    }

    init(
        name: String,
        normalizedName: String,
        unitSymbol: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        goalDirection: BodyMeasurementGoalDirection? = nil,
        goalTargetValue: Double? = nil,
        goalNotes: String = ""
    ) {
        self.name = name
        self.normalizedName = normalizedName
        self.unitSymbol = unitSymbol
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.goalDirectionRaw = goalDirection?.rawValue
        self.goalTargetValue = goalTargetValue
        self.goalNotesRaw = goalNotes
        self.entries = []
    }
}
