import Foundation
import SwiftData

struct BodyMeasurementLatestValue: Identifiable {
    let metricID: PersistentIdentifier
    let metricName: String
    let unitSymbol: String
    let value: Double
    let recordedAt: Date

    var id: PersistentIdentifier { metricID }
}

struct BodyMeasurementHistoryPoint: Identifiable {
    let date: Date
    let averageValue: Double
    let minimumValue: Double
    let maximumValue: Double
    let entryCount: Int

    var id: Date { date }
}

struct BodyMeasurementHistorySummary {
    let pointCount: Int
    let entryCount: Int
    let currentValue: Double
    let startingValue: Double
    let lowestValue: Double
    let highestValue: Double
    let changeFromStart: Double

    static let empty = BodyMeasurementHistorySummary(
        pointCount: 0,
        entryCount: 0,
        currentValue: 0,
        startingValue: 0,
        lowestValue: 0,
        highestValue: 0,
        changeFromStart: 0
    )
}

struct BodyMeasurementGoalStatus {
    let direction: BodyMeasurementGoalDirection
    let targetValue: Double
    let currentValue: Double
    let startingValue: Double?
    let unitSymbol: String

    var isAchieved: Bool {
        switch direction {
        case .decrease:
            return currentValue <= targetValue
        case .increase:
            return currentValue >= targetValue
        }
    }

    var progress: Double {
        switch direction {
        case .increase:
            guard targetValue > 0 else { return 0 }
            return min(max(currentValue / targetValue, 0), 1)
        case .decrease:
            guard let startingValue, startingValue > targetValue else {
                return isAchieved ? 1 : 0
            }
            let span = startingValue - targetValue
            let completed = startingValue - currentValue
            return min(max(completed / span, 0), 1)
        }
    }

    var statusText: String {
        if isAchieved {
            return "Goal reached."
        }

        switch direction {
        case .decrease:
            return "Reduce \(remainingValue.formatted(.number.precision(.fractionLength(0...2)))) \(unitSymbol) more."
        case .increase:
            return "Increase \(remainingValue.formatted(.number.precision(.fractionLength(0...2)))) \(unitSymbol) more."
        }
    }

    private var remainingValue: Double {
        switch direction {
        case .decrease:
            return max(currentValue - targetValue, 0)
        case .increase:
            return max(targetValue - currentValue, 0)
        }
    }
}

struct BodyTrackingSnapshot {
    let totalMetricCount: Int
    let enabledMetricCount: Int
    let totalEntryCount: Int
    let latestEntryDate: Date?
    let latestValues: [BodyMeasurementLatestValue]

    private let entriesByMetricID: [PersistentIdentifier: [BodyMeasurementEntry]]
    private let calendar: Calendar

    static let empty = BodyTrackingSnapshot(
        totalMetricCount: 0,
        enabledMetricCount: 0,
        totalEntryCount: 0,
        latestEntryDate: nil,
        latestValues: [],
        entriesByMetricID: [:],
        calendar: .current
    )

    private init(
        totalMetricCount: Int,
        enabledMetricCount: Int,
        totalEntryCount: Int,
        latestEntryDate: Date?,
        latestValues: [BodyMeasurementLatestValue],
        entriesByMetricID: [PersistentIdentifier: [BodyMeasurementEntry]],
        calendar: Calendar
    ) {
        self.totalMetricCount = totalMetricCount
        self.enabledMetricCount = enabledMetricCount
        self.totalEntryCount = totalEntryCount
        self.latestEntryDate = latestEntryDate
        self.latestValues = latestValues
        self.entriesByMetricID = entriesByMetricID
        self.calendar = calendar
    }

    init(metrics: [BodyMeasurementMetric], calendar: Calendar = .current) {
        guard !metrics.isEmpty else {
            self = .empty
            return
        }

        let enabledMetrics = metrics.filter(\.isEnabled)
        let entriesByMetricID = Dictionary(
            uniqueKeysWithValues: metrics.map { metric in
                (
                    metric.persistentModelID,
                    metric.entries.sorted(using: [KeyPathComparator(\BodyMeasurementEntry.recordedAt)])
                )
            }
        )

        let latestValues = metrics.compactMap { metric -> BodyMeasurementLatestValue? in
            guard
                let entry = entriesByMetricID[metric.persistentModelID]?.last
            else {
                return nil
            }

            return BodyMeasurementLatestValue(
                metricID: metric.persistentModelID,
                metricName: metric.name,
                unitSymbol: metric.unitSymbol,
                value: entry.value,
                recordedAt: entry.recordedAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.recordedAt == rhs.recordedAt {
                return lhs.metricName.localizedCaseInsensitiveCompare(rhs.metricName) == .orderedAscending
            }
            return lhs.recordedAt > rhs.recordedAt
        }

        self.totalMetricCount = metrics.count
        self.enabledMetricCount = enabledMetrics.count
        self.totalEntryCount = metrics.reduce(0) { $0 + $1.entries.count }
        self.latestEntryDate = latestValues.map(\.recordedAt).max()
        self.latestValues = latestValues
        self.entriesByMetricID = entriesByMetricID
        self.calendar = calendar
    }

    func progression(
        for metric: BodyMeasurementMetric,
        range: StatisticsTimeRange,
        granularity: ExerciseProgressionGranularity
    ) -> [BodyMeasurementHistoryPoint] {
        guard var entries = entriesByMetricID[metric.persistentModelID], !entries.isEmpty else {
            return []
        }

        if let latestDate = entries.last?.recordedAt,
           let startDate = range.startDate(relativeTo: latestDate, calendar: calendar) {
            let boundedStartDate = calendar.startOfDay(for: startDate)
            entries = entries.filter { calendar.startOfDay(for: $0.recordedAt) >= boundedStartDate }
        }

        let groupedEntries = Dictionary(grouping: entries) { entry in
            bucketDate(for: entry.recordedAt, granularity: granularity)
        }

        return groupedEntries.keys.sorted().compactMap { date in
            guard let bucketEntries = groupedEntries[date], !bucketEntries.isEmpty else {
                return nil
            }

            let values = bucketEntries.map(\.value)
            let averageValue = values.reduce(0, +) / Double(values.count)
            return BodyMeasurementHistoryPoint(
                date: date,
                averageValue: averageValue,
                minimumValue: values.min() ?? averageValue,
                maximumValue: values.max() ?? averageValue,
                entryCount: bucketEntries.count
            )
        }
    }

    func summary(
        for metric: BodyMeasurementMetric,
        range: StatisticsTimeRange,
        granularity: ExerciseProgressionGranularity
    ) -> BodyMeasurementHistorySummary {
        let points = progression(for: metric, range: range, granularity: granularity)
        guard !points.isEmpty else {
            return .empty
        }

        let values = points.map(\.averageValue)
        let currentValue = values.last ?? 0
        let startingValue = values.first ?? 0

        return BodyMeasurementHistorySummary(
            pointCount: points.count,
            entryCount: points.reduce(0) { $0 + $1.entryCount },
            currentValue: currentValue,
            startingValue: startingValue,
            lowestValue: values.min() ?? currentValue,
            highestValue: values.max() ?? currentValue,
            changeFromStart: currentValue - startingValue
        )
    }

    func goalStatus(for metric: BodyMeasurementMetric) -> BodyMeasurementGoalStatus? {
        guard
            let direction = metric.goalDirection,
            let targetValue = metric.goalTargetValue,
            targetValue > 0,
            let entries = entriesByMetricID[metric.persistentModelID],
            let firstEntry = entries.first,
            let latestEntry = entries.last
        else {
            return nil
        }

        return BodyMeasurementGoalStatus(
            direction: direction,
            targetValue: targetValue,
            currentValue: latestEntry.value,
            startingValue: firstEntry.value,
            unitSymbol: metric.unitSymbol
        )
    }

    private func bucketDate(for date: Date, granularity: ExerciseProgressionGranularity) -> Date {
        switch granularity {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let components = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        case .month:
            let components = calendar.dateComponents([.calendar, .year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        }
    }
}
