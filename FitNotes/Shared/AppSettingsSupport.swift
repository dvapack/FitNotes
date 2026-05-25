import Foundation

struct AppSettingsSnapshot {
    let unitSystem: AppUnitSystem
    let weightIncrement: Double
    let calendarWeekStart: CalendarWeekStart
    let personalRecordBehavior: PersonalRecordBehavior
    let setCompletionBehavior: SetCompletionBehavior
    let nextSetBehavior: NextSetBehavior
    let showsRestTimer: Bool
    let keepScreenAwakeDuringWorkout: Bool
    let showsHomeOverview: Bool
    let showsRecentWorkouts: Bool

    init(settings: AppSettings?) {
        self.unitSystem = settings?.unitSystem ?? .kilograms
        self.weightIncrement = settings?.weightIncrement ?? 2.5
        self.calendarWeekStart = settings?.calendarWeekStart ?? .monday
        self.personalRecordBehavior = settings?.personalRecordBehavior ?? .includeEstimatedOneRepMax
        self.setCompletionBehavior = settings?.setCompletionBehavior ?? .markCompleted
        self.nextSetBehavior = settings?.nextSetBehavior ?? .repeatPreviousValues
        self.showsRestTimer = settings?.showsRestTimer ?? true
        self.keepScreenAwakeDuringWorkout = settings?.keepScreenAwakeDuringWorkout ?? true
        self.showsHomeOverview = settings?.showsHomeOverview ?? true
        self.showsRecentWorkouts = settings?.showsRecentWorkouts ?? true
    }

    func calendar(base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = calendarWeekStart.firstWeekday
        return calendar
    }

    func orderedVeryShortWeekdaySymbols(base: Calendar = .current) -> [String] {
        let symbols = calendar(base: base).veryShortWeekdaySymbols
        let offset = max(calendarWeekStart.firstWeekday - 1, 0)
        guard offset > 0 else {
            return symbols
        }

        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    func storedWeight(fromDisplayWeight value: Double) -> Double {
        switch unitSystem {
        case .kilograms:
            return value
        case .pounds:
            return value / 2.204_622_621_8
        }
    }

    func displayWeight(fromStoredWeight value: Double) -> Double {
        switch unitSystem {
        case .kilograms:
            return value
        case .pounds:
            return value * 2.204_622_621_8
        }
    }

    func formatWeight(_ storedWeight: Double) -> String {
        let value = displayWeight(fromStoredWeight: storedWeight)
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unitSystem.symbol)"
    }

    func formatWeightInput(_ storedWeight: Double) -> String {
        displayWeight(fromStoredWeight: storedWeight).formatted(.number.precision(.fractionLength(0...2)))
    }

    func formatVolume(_ storedVolume: Double) -> String {
        let value = displayWeight(fromStoredWeight: storedVolume)
        return value.formatted(.number.precision(.fractionLength(0...0))) + " \(unitSystem.symbol)·reps"
    }

    func formatIncrement() -> String {
        "\(weightIncrement.formatted(.number.precision(.fractionLength(0...2)))) \(unitSystem.symbol)"
    }
}
