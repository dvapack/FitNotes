import Foundation
import SwiftData

enum BodyMeasurementStoreError: LocalizedError, Equatable {
    case emptyMeasurementName
    case emptyUnit
    case duplicateMeasurement
    case invalidValue
    case invalidGoalTarget

    var errorDescription: String? {
        switch self {
        case .emptyMeasurementName:
            return "Measurement names can't be blank."
        case .emptyUnit:
            return "Measurement units can't be blank."
        case .duplicateMeasurement:
            return "A body measurement with this name already exists."
        case .invalidValue:
            return "Measurement values must be greater than zero."
        case .invalidGoalTarget:
            return "Goal targets must be greater than zero."
        }
    }
}

@MainActor
struct BodyMeasurementStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchMeasurements(includeDisabled: Bool = true) throws -> [BodyMeasurementMetric] {
        let measurements = try context.fetch(FetchDescriptor(
            sortBy: [
                SortDescriptor(\BodyMeasurementMetric.sortOrder),
                SortDescriptor(\BodyMeasurementMetric.name)
            ]
        ))

        if includeDisabled {
            return measurements.sorted { lhs, rhs in
                if lhs.isEnabled != rhs.isEnabled {
                    return lhs.isEnabled && !rhs.isEnabled
                }

                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        return measurements.filter { $0.isEnabled }
    }

    func fetchEntries(for metric: BodyMeasurementMetric) throws -> [BodyMeasurementEntry] {
        try context.fetch(FetchDescriptor<BodyMeasurementEntry>(
            sortBy: [SortDescriptor(\BodyMeasurementEntry.recordedAt, order: .reverse)]
        ))
        .filter { $0.metric?.persistentModelID == metric.persistentModelID }
    }

    @discardableResult
    func createMeasurement(
        name: String,
        unitSymbol: String,
        isEnabled: Bool = true,
        goalDirection: BodyMeasurementGoalDirection? = nil,
        goalTargetValue: Double? = nil,
        goalNotes: String = ""
    ) throws -> BodyMeasurementMetric {
        let normalizedName = try validateName(name)
        let trimmedUnit = try validateUnit(unitSymbol)
        try validateGoal(direction: goalDirection, targetValue: goalTargetValue)

        if try fetchMeasurements().contains(where: { $0.normalizedName == normalizedName }) {
            throw BodyMeasurementStoreError.duplicateMeasurement
        }

        let nextSortOrder = (try fetchMeasurements().map(\.sortOrder).max() ?? -1) + 1
        let metric = BodyMeasurementMetric(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedName: normalizedName,
            unitSymbol: trimmedUnit,
            isEnabled: isEnabled,
            sortOrder: nextSortOrder,
            goalDirection: goalDirection,
            goalTargetValue: goalTargetValue,
            goalNotes: goalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(metric)
        try context.save()
        return metric
    }

    func updateMeasurement(
        _ metric: BodyMeasurementMetric,
        name: String,
        unitSymbol: String,
        isEnabled: Bool,
        goalDirection: BodyMeasurementGoalDirection?,
        goalTargetValue: Double?,
        goalNotes: String
    ) throws {
        let normalizedName = try validateName(name)
        let trimmedUnit = try validateUnit(unitSymbol)
        try validateGoal(direction: goalDirection, targetValue: goalTargetValue)

        if try fetchMeasurements().contains(where: {
            $0.persistentModelID != metric.persistentModelID && $0.normalizedName == normalizedName
        }) {
            throw BodyMeasurementStoreError.duplicateMeasurement
        }

        metric.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        metric.normalizedName = normalizedName
        metric.unitSymbol = trimmedUnit
        metric.isEnabled = isEnabled
        metric.goalDirection = goalDirection
        metric.goalTargetValue = goalTargetValue
        metric.goalNotes = goalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    func moveMeasurements(fromOffsets: IndexSet, toOffset: Int) throws {
        var measurements = try fetchMeasurements()
        let movingItems = fromOffsets.map { measurements[$0] }
        measurements.remove(atOffsets: fromOffsets)
        let destination = min(
            max(toOffset - fromOffsets.filter { $0 < toOffset }.count, 0),
            measurements.count
        )
        measurements.insert(contentsOf: movingItems, at: destination)

        for (index, measurement) in measurements.enumerated() {
            measurement.sortOrder = index
        }

        try context.save()
    }

    func deleteMeasurement(_ metric: BodyMeasurementMetric) throws {
        context.delete(metric)
        try context.save()
    }

    @discardableResult
    func addEntry(
        to metric: BodyMeasurementMetric,
        value: Double,
        recordedAt: Date,
        note: String = ""
    ) throws -> BodyMeasurementEntry {
        guard value > 0 else {
            throw BodyMeasurementStoreError.invalidValue
        }

        let entry = BodyMeasurementEntry(
            recordedAt: recordedAt,
            value: value,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            metric: metric
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    func updateEntry(
        _ entry: BodyMeasurementEntry,
        value: Double,
        recordedAt: Date,
        note: String
    ) throws {
        guard value > 0 else {
            throw BodyMeasurementStoreError.invalidValue
        }

        entry.value = value
        entry.recordedAt = recordedAt
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    func deleteEntry(_ entry: BodyMeasurementEntry) throws {
        context.delete(entry)
        try context.save()
    }

    private func validateName(_ value: String) throws -> String {
        let normalized = value.normalizedCatalogName
        guard !normalized.isEmpty else {
            throw BodyMeasurementStoreError.emptyMeasurementName
        }
        return normalized
    }

    private func validateUnit(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BodyMeasurementStoreError.emptyUnit
        }
        return trimmed
    }

    private func validateGoal(direction: BodyMeasurementGoalDirection?, targetValue: Double?) throws {
        if let targetValue, targetValue <= 0 {
            throw BodyMeasurementStoreError.invalidGoalTarget
        }

        if direction == nil {
            return
        }

        guard let targetValue, targetValue > 0 else {
            throw BodyMeasurementStoreError.invalidGoalTarget
        }
    }
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            remove(at: index)
        }
    }
}
