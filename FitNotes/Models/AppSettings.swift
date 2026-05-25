import Foundation
import SwiftData

enum AppUnitSystem: String, Codable, CaseIterable, Identifiable {
    case kilograms
    case pounds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kilograms:
            return "Kilograms"
        case .pounds:
            return "Pounds"
        }
    }

    var symbol: String {
        switch self {
        case .kilograms:
            return "kg"
        case .pounds:
            return "lb"
        }
    }
}

enum CalendarWeekStart: String, Codable, CaseIterable, Identifiable {
    case sunday
    case monday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunday:
            return "Sunday"
        case .monday:
            return "Monday"
        }
    }

    var firstWeekday: Int {
        switch self {
        case .sunday:
            return 1
        case .monday:
            return 2
        }
    }
}

enum PersonalRecordBehavior: String, Codable, CaseIterable, Identifiable {
    case actualOnly
    case includeEstimatedOneRepMax

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actualOnly:
            return "Actual Results Only"
        case .includeEstimatedOneRepMax:
            return "Include Estimated 1RM"
        }
    }
}

enum SetCompletionBehavior: String, Codable, CaseIterable, Identifiable {
    case markCompleted
    case leaveIncomplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markCompleted:
            return "Mark Sets Complete"
        case .leaveIncomplete:
            return "Leave Sets Incomplete"
        }
    }

    var completesSetsByDefault: Bool {
        self == .markCompleted
    }
}

enum NextSetBehavior: String, Codable, CaseIterable, Identifiable {
    case clearFields
    case repeatPreviousValues

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clearFields:
            return "Clear Weight and Reps"
        case .repeatPreviousValues:
            return "Repeat Previous Weight and Reps"
        }
    }
}

@Model
final class AppSettings {
    var createdAt: Date
    var unitSystemRaw: String
    var weightIncrement: Double
    var calendarWeekStartRaw: String
    var personalRecordBehaviorRaw: String
    var setCompletionBehaviorRaw: String
    var nextSetBehaviorRaw: String
    var showsRestTimer: Bool
    var keepScreenAwakeDuringWorkout: Bool
    var showsHomeOverview: Bool
    var showsRecentWorkouts: Bool

    var unitSystem: AppUnitSystem {
        get { AppUnitSystem(rawValue: unitSystemRaw) ?? .kilograms }
        set { unitSystemRaw = newValue.rawValue }
    }

    var calendarWeekStart: CalendarWeekStart {
        get { CalendarWeekStart(rawValue: calendarWeekStartRaw) ?? .monday }
        set { calendarWeekStartRaw = newValue.rawValue }
    }

    var personalRecordBehavior: PersonalRecordBehavior {
        get { PersonalRecordBehavior(rawValue: personalRecordBehaviorRaw) ?? .includeEstimatedOneRepMax }
        set { personalRecordBehaviorRaw = newValue.rawValue }
    }

    var setCompletionBehavior: SetCompletionBehavior {
        get { SetCompletionBehavior(rawValue: setCompletionBehaviorRaw) ?? .markCompleted }
        set { setCompletionBehaviorRaw = newValue.rawValue }
    }

    var nextSetBehavior: NextSetBehavior {
        get { NextSetBehavior(rawValue: nextSetBehaviorRaw) ?? .repeatPreviousValues }
        set { nextSetBehaviorRaw = newValue.rawValue }
    }

    init(
        createdAt: Date = .now,
        unitSystem: AppUnitSystem = .kilograms,
        weightIncrement: Double = 2.5,
        calendarWeekStart: CalendarWeekStart = .monday,
        personalRecordBehavior: PersonalRecordBehavior = .includeEstimatedOneRepMax,
        setCompletionBehavior: SetCompletionBehavior = .markCompleted,
        nextSetBehavior: NextSetBehavior = .repeatPreviousValues,
        showsRestTimer: Bool = true,
        keepScreenAwakeDuringWorkout: Bool = true,
        showsHomeOverview: Bool = true,
        showsRecentWorkouts: Bool = true
    ) {
        self.createdAt = createdAt
        self.unitSystemRaw = unitSystem.rawValue
        self.weightIncrement = weightIncrement
        self.calendarWeekStartRaw = calendarWeekStart.rawValue
        self.personalRecordBehaviorRaw = personalRecordBehavior.rawValue
        self.setCompletionBehaviorRaw = setCompletionBehavior.rawValue
        self.nextSetBehaviorRaw = nextSetBehavior.rawValue
        self.showsRestTimer = showsRestTimer
        self.keepScreenAwakeDuringWorkout = keepScreenAwakeDuringWorkout
        self.showsHomeOverview = showsHomeOverview
        self.showsRecentWorkouts = showsRecentWorkouts
    }
}
