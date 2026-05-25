import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum DataPortabilityError: LocalizedError, Equatable {
    case unsupportedBackupVersion(Int)
    case invalidBackup
    case multipleDraftWorkouts
    case invalidSetData

    var errorDescription: String? {
        switch self {
        case let .unsupportedBackupVersion(version):
            return "This backup uses unsupported format version \(version)."
        case .invalidBackup:
            return "The selected backup file isn't a valid FitNotes export."
        case .multipleDraftWorkouts:
            return "This backup contains more than one draft workout, so it can't be restored safely."
        case .invalidSetData:
            return "This backup contains an invalid set with zero or negative weight or reps."
        }
    }
}

struct BackupPreview {
    let formatVersion: Int
    let exportedAt: Date
    let muscleGroupCount: Int
    let exerciseCount: Int
    let workoutCount: Int
    let setCount: Int
    let bodyMeasurementCount: Int
    let bodyMeasurementEntryCount: Int
}

struct BackupRestoreResult {
    let muscleGroupCount: Int
    let exerciseCount: Int
    let workoutCount: Int
    let setCount: Int
    let bodyMeasurementCount: Int
    let bodyMeasurementEntryCount: Int
}

struct DataResetResult {
    let deletedWorkoutCount: Int
    let deletedSetCount: Int
    let deletedExerciseCount: Int
    let deletedMuscleGroupCount: Int
    let deletedSettingsCount: Int
    let deletedBodyMeasurementCount: Int
    let deletedBodyMeasurementEntryCount: Int
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct WorkoutCSVFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
struct DataPortabilityService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func exportBackupData() throws -> Data {
        let settings = try AppSettingsStore(context: context).fetchSettings().first
        let muscleGroups = try fetchMuscleGroups()
        let exercises = try fetchExercises()
        let workouts = try fetchWorkouts()
        let bodyMeasurements = try fetchBodyMeasurements()
        let setCounts = Dictionary(grouping: try fetchSets(), by: \.workout?.persistentModelID)
        let bodyEntries = Dictionary(grouping: try fetchBodyMeasurementEntries(), by: \.metric?.persistentModelID)

        let muscleGroupReferenceIDs = Dictionary(
            uniqueKeysWithValues: muscleGroups.map { ($0.persistentModelID, UUID().uuidString) }
        )
        let exerciseReferenceIDs = Dictionary(
            uniqueKeysWithValues: exercises.map { ($0.persistentModelID, UUID().uuidString) }
        )

        let payload = AppBackupPayload(
            formatVersion: 2,
            exportedAt: .now,
            settings: settings.map(BackupSettingsPayload.init),
            muscleGroups: muscleGroups.map { group in
                BackupMuscleGroupPayload(
                    id: muscleGroupReferenceIDs[group.persistentModelID] ?? UUID().uuidString,
                    name: group.name,
                    sortOrder: group.sortOrder,
                    colorHex: group.colorHex
                )
            },
            exercises: exercises.map { exercise in
                BackupExercisePayload(
                    id: exerciseReferenceIDs[exercise.persistentModelID] ?? UUID().uuidString,
                    muscleGroupID: exercise.muscleGroup.flatMap { muscleGroupReferenceIDs[$0.persistentModelID] },
                    name: exercise.name,
                    normalizedName: exercise.normalizedName,
                    isCustom: exercise.isCustom,
                    createdAt: exercise.createdAt,
                    notes: exercise.notes,
                    isFavorite: exercise.isFavorite,
                    exerciseType: exercise.exerciseType,
                    preferredWeightUnit: exercise.preferredWeightUnit,
                    defaultRestSeconds: exercise.defaultRestSeconds,
                    defaultProgressionView: exercise.defaultProgressionView,
                    goalMetric: exercise.goalMetric,
                    goalTargetValue: exercise.goalTargetValue,
                    goalNotes: exercise.goalNotes
                )
            },
            workouts: workouts.map { workout in
                BackupWorkoutPayload(
                    date: workout.date,
                    startedAt: workout.startedAt,
                    finishedAt: workout.finishedAt,
                    comment: workout.comment,
                    sets: (setCounts[workout.persistentModelID] ?? [])
                        .sorted(using: [KeyPathComparator(\WorkoutSet.exerciseOrder), KeyPathComparator(\WorkoutSet.setOrder)])
                        .map { workoutSet in
                            BackupWorkoutSetPayload(
                                exerciseID: workoutSet.exercise.flatMap { exerciseReferenceIDs[$0.persistentModelID] },
                                exerciseOrder: workoutSet.exerciseOrder,
                                setOrder: workoutSet.setOrder,
                                weight: workoutSet.weight,
                                reps: workoutSet.reps,
                                comment: workoutSet.comment,
                                isCompleted: workoutSet.isCompleted,
                                exerciseNameSnapshot: workoutSet.exerciseNameSnapshot ?? "",
                                muscleGroupNameSnapshot: workoutSet.muscleGroupNameSnapshot ?? ""
                            )
                        }
                )
            },
            bodyMeasurements: bodyMeasurements.map { metric in
                BackupBodyMeasurementPayload(
                    id: UUID().uuidString,
                    name: metric.name,
                    normalizedName: metric.normalizedName,
                    unitSymbol: metric.unitSymbol,
                    isEnabled: metric.isEnabled,
                    sortOrder: metric.sortOrder,
                    createdAt: metric.createdAt,
                    goalDirection: metric.goalDirection,
                    goalTargetValue: metric.goalTargetValue,
                    goalNotes: metric.goalNotes,
                    entries: (bodyEntries[metric.persistentModelID] ?? [])
                        .sorted(using: [KeyPathComparator(\BodyMeasurementEntry.recordedAt)])
                        .map { entry in
                            BackupBodyMeasurementEntryPayload(
                                recordedAt: entry.recordedAt,
                                value: entry.value,
                                note: entry.note
                            )
                        }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    func previewBackup(from data: Data) throws -> BackupPreview {
        let payload = try decodeBackupPayload(from: data)
        return BackupPreview(
            formatVersion: payload.formatVersion,
            exportedAt: payload.exportedAt,
            muscleGroupCount: payload.muscleGroups.count,
            exerciseCount: payload.exercises.count,
            workoutCount: payload.workouts.count,
            setCount: payload.workouts.reduce(into: 0) { $0 += $1.sets.count },
            bodyMeasurementCount: payload.bodyMeasurements.count,
            bodyMeasurementEntryCount: payload.bodyMeasurements.reduce(into: 0) { $0 += $1.entries.count }
        )
    }

    func restoreBackup(from data: Data) throws -> BackupRestoreResult {
        let payload = try decodeBackupPayload(from: data)
        try validate(payload)

        try deleteAllData()

        if let settingsPayload = payload.settings {
            context.insert(settingsPayload.makeModel())
        } else {
            _ = try AppSettingsStore(context: context).fetchOrCreateSettings()
        }

        var muscleGroupsByID: [String: MuscleGroup] = [:]
        for groupPayload in payload.muscleGroups.sorted(by: { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }) {
            let group = groupPayload.makeModel()
            context.insert(group)
            muscleGroupsByID[groupPayload.id] = group
        }

        var exercisesByID: [String: Exercise] = [:]
        for exercisePayload in payload.exercises.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let exercise = exercisePayload.makeModel(muscleGroup: exercisePayload.muscleGroupID.flatMap { muscleGroupsByID[$0] })
            context.insert(exercise)
            exercisesByID[exercisePayload.id] = exercise
        }

        for workoutPayload in payload.workouts.sorted(by: { $0.startedAt < $1.startedAt }) {
            let workout = workoutPayload.makeModel()
            context.insert(workout)

            for setPayload in workoutPayload.sets.sorted(by: { lhs, rhs in
                if lhs.exerciseOrder == rhs.exerciseOrder {
                    return lhs.setOrder < rhs.setOrder
                }
                return lhs.exerciseOrder < rhs.exerciseOrder
            }) {
                let workoutSet = setPayload.makeModel(
                    workout: workout,
                    exercise: setPayload.exerciseID.flatMap { exercisesByID[$0] }
                )
                context.insert(workoutSet)
            }
        }

        for measurementPayload in payload.bodyMeasurements.sorted(by: { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }) {
            let metric = measurementPayload.makeModel()
            context.insert(metric)

            for entryPayload in measurementPayload.entries.sorted(by: { $0.recordedAt < $1.recordedAt }) {
                context.insert(entryPayload.makeModel(metric: metric))
            }
        }

        try context.save()

        return BackupRestoreResult(
            muscleGroupCount: payload.muscleGroups.count,
            exerciseCount: payload.exercises.count,
            workoutCount: payload.workouts.count,
            setCount: payload.workouts.reduce(into: 0) { $0 += $1.sets.count },
            bodyMeasurementCount: payload.bodyMeasurements.count,
            bodyMeasurementEntryCount: payload.bodyMeasurements.reduce(into: 0) { $0 += $1.entries.count }
        )
    }

    func exportWorkoutCSV(using settings: AppSettingsSnapshot) throws -> Data {
        let workouts = try fetchWorkouts()
        let setsByWorkout = Dictionary(grouping: try fetchSets(), by: \.workout?.persistentModelID)
        let lines = [
            [
                "Workout Date",
                "Started At",
                "Finished At",
                "Workout Status",
                "Workout Comment",
                "Muscle Group",
                "Exercise",
                "Exercise Deleted",
                "Exercise Order",
                "Set Order",
                "Weight",
                "Weight Unit",
                "Reps",
                "Set Completed",
                "Set Comment"
            ].joined(separator: ",")
        ] + workouts.flatMap { workout in
            let sortedSets = (setsByWorkout[workout.persistentModelID] ?? [])
                .sorted(using: [KeyPathComparator(\WorkoutSet.exerciseOrder), KeyPathComparator(\WorkoutSet.setOrder)])

            return sortedSets.map { workoutSet in
                [
                    csvField(Self.dayFormatter.string(from: workout.date)),
                    csvField(Self.dateTimeFormatter.string(from: workout.startedAt)),
                    csvField(workout.finishedAt.map(Self.dateTimeFormatter.string(from:)) ?? ""),
                    csvField(workout.finishedAt == nil ? "Draft" : "Finished"),
                    csvField(workout.comment),
                    csvField(workoutSet.muscleGroupNameSnapshot ?? workoutSet.exercise?.muscleGroup?.name ?? "Uncategorized"),
                    csvField(workoutSet.exerciseNameSnapshot ?? workoutSet.exercise?.name ?? "Unknown Exercise"),
                    csvField(workoutSet.exercise == nil ? "Yes" : "No"),
                    csvField(String(workoutSet.exerciseOrder)),
                    csvField(String(workoutSet.setOrder)),
                    csvField(Self.numberString(from: settings.displayWeight(fromStoredWeight: workoutSet.weight))),
                    csvField(settings.unitSystem.symbol),
                    csvField(String(workoutSet.reps)),
                    csvField(workoutSet.isCompleted ? "Yes" : "No"),
                    csvField(workoutSet.comment)
                ].joined(separator: ",")
            }
        }

        return Data(lines.joined(separator: "\n").utf8)
    }

    func resetWorkouts() throws -> DataResetResult {
        let workoutCount = try context.fetchCount(FetchDescriptor<Workout>())
        let setCount = try context.fetchCount(FetchDescriptor<WorkoutSet>())

        for workout in try fetchWorkouts() {
            context.delete(workout)
        }
        try context.save()

        return DataResetResult(
            deletedWorkoutCount: workoutCount,
            deletedSetCount: setCount,
            deletedExerciseCount: 0,
            deletedMuscleGroupCount: 0,
            deletedSettingsCount: 0,
            deletedBodyMeasurementCount: 0,
            deletedBodyMeasurementEntryCount: 0
        )
    }

    func resetAllData() throws -> DataResetResult {
        let workoutCount = try context.fetchCount(FetchDescriptor<Workout>())
        let setCount = try context.fetchCount(FetchDescriptor<WorkoutSet>())
        let exerciseCount = try context.fetchCount(FetchDescriptor<Exercise>())
        let muscleGroupCount = try context.fetchCount(FetchDescriptor<MuscleGroup>())
        let settingsCount = try context.fetchCount(FetchDescriptor<AppSettings>())
        let bodyMeasurementCount = try context.fetchCount(FetchDescriptor<BodyMeasurementMetric>())
        let bodyMeasurementEntryCount = try context.fetchCount(FetchDescriptor<BodyMeasurementEntry>())

        try deleteAllData()
        try SeedDataService(context: context).seedIfNeeded()
        _ = try AppSettingsStore(context: context).fetchOrCreateSettings()

        return DataResetResult(
            deletedWorkoutCount: workoutCount,
            deletedSetCount: setCount,
            deletedExerciseCount: exerciseCount,
            deletedMuscleGroupCount: muscleGroupCount,
            deletedSettingsCount: settingsCount,
            deletedBodyMeasurementCount: bodyMeasurementCount,
            deletedBodyMeasurementEntryCount: bodyMeasurementEntryCount
        )
    }

    private func decodeBackupPayload(from data: Data) throws -> AppBackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let payload = try decoder.decode(AppBackupPayload.self, from: data)
            guard (1...2).contains(payload.formatVersion) else {
                throw DataPortabilityError.unsupportedBackupVersion(payload.formatVersion)
            }
            return payload
        } catch let error as DataPortabilityError {
            throw error
        } catch {
            throw DataPortabilityError.invalidBackup
        }
    }

    private func validate(_ payload: AppBackupPayload) throws {
        if payload.workouts.filter({ $0.finishedAt == nil }).count > 1 {
            throw DataPortabilityError.multipleDraftWorkouts
        }

        if payload.workouts.flatMap(\.sets).contains(where: { $0.weight <= 0 || $0.reps <= 0 }) {
            throw DataPortabilityError.invalidSetData
        }

        if payload.bodyMeasurements.flatMap(\.entries).contains(where: { $0.value <= 0 }) {
            throw DataPortabilityError.invalidBackup
        }
    }

    private func deleteAllData() throws {
        for workout in try fetchWorkouts() {
            context.delete(workout)
        }

        for exercise in try fetchExercises() {
            context.delete(exercise)
        }

        for muscleGroup in try fetchMuscleGroups() {
            context.delete(muscleGroup)
        }

        for settings in try AppSettingsStore(context: context).fetchSettings() {
            context.delete(settings)
        }

        for metric in try fetchBodyMeasurements() {
            context.delete(metric)
        }

        try context.save()
    }

    private func fetchMuscleGroups() throws -> [MuscleGroup] {
        try context.fetch(FetchDescriptor(
            sortBy: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)]
        ))
    }

    private func fetchExercises() throws -> [Exercise] {
        try context.fetch(FetchDescriptor(
            sortBy: [SortDescriptor(\Exercise.name), SortDescriptor(\Exercise.createdAt)]
        ))
    }

    private func fetchWorkouts() throws -> [Workout] {
        try context.fetch(FetchDescriptor(
            sortBy: [SortDescriptor(\Workout.startedAt), SortDescriptor(\Workout.date)]
        ))
    }

    private func fetchSets() throws -> [WorkoutSet] {
        try context.fetch(FetchDescriptor(
            sortBy: [SortDescriptor(\WorkoutSet.exerciseOrder), SortDescriptor(\WorkoutSet.setOrder)]
        ))
    }

    private func fetchBodyMeasurements() throws -> [BodyMeasurementMetric] {
        try context.fetch(FetchDescriptor(
            sortBy: [SortDescriptor(\BodyMeasurementMetric.sortOrder), SortDescriptor(\BodyMeasurementMetric.name)]
        ))
    }

    private func fetchBodyMeasurementEntries() throws -> [BodyMeasurementEntry] {
        try context.fetch(FetchDescriptor(
            sortBy: [SortDescriptor(\BodyMeasurementEntry.recordedAt)]
        ))
    }

    private func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func numberString(from value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

private struct AppBackupPayload: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let settings: BackupSettingsPayload?
    let muscleGroups: [BackupMuscleGroupPayload]
    let exercises: [BackupExercisePayload]
    let workouts: [BackupWorkoutPayload]
    let bodyMeasurements: [BackupBodyMeasurementPayload]

    init(
        formatVersion: Int,
        exportedAt: Date,
        settings: BackupSettingsPayload?,
        muscleGroups: [BackupMuscleGroupPayload],
        exercises: [BackupExercisePayload],
        workouts: [BackupWorkoutPayload],
        bodyMeasurements: [BackupBodyMeasurementPayload]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.muscleGroups = muscleGroups
        self.exercises = exercises
        self.workouts = workouts
        self.bodyMeasurements = bodyMeasurements
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case settings
        case muscleGroups
        case exercises
        case workouts
        case bodyMeasurements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        settings = try container.decodeIfPresent(BackupSettingsPayload.self, forKey: .settings)
        muscleGroups = try container.decode([BackupMuscleGroupPayload].self, forKey: .muscleGroups)
        exercises = try container.decode([BackupExercisePayload].self, forKey: .exercises)
        workouts = try container.decode([BackupWorkoutPayload].self, forKey: .workouts)
        bodyMeasurements = try container.decodeIfPresent([BackupBodyMeasurementPayload].self, forKey: .bodyMeasurements) ?? []
    }
}

private struct BackupSettingsPayload: Codable {
    let createdAt: Date
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

    init(settings: AppSettings) {
        createdAt = settings.createdAt
        unitSystem = settings.unitSystem
        weightIncrement = settings.weightIncrement
        calendarWeekStart = settings.calendarWeekStart
        personalRecordBehavior = settings.personalRecordBehavior
        setCompletionBehavior = settings.setCompletionBehavior
        nextSetBehavior = settings.nextSetBehavior
        showsRestTimer = settings.showsRestTimer
        keepScreenAwakeDuringWorkout = settings.keepScreenAwakeDuringWorkout
        showsHomeOverview = settings.showsHomeOverview
        showsRecentWorkouts = settings.showsRecentWorkouts
    }

    func makeModel() -> AppSettings {
        AppSettings(
            createdAt: createdAt,
            unitSystem: unitSystem,
            weightIncrement: weightIncrement,
            calendarWeekStart: calendarWeekStart,
            personalRecordBehavior: personalRecordBehavior,
            setCompletionBehavior: setCompletionBehavior,
            nextSetBehavior: nextSetBehavior,
            showsRestTimer: showsRestTimer,
            keepScreenAwakeDuringWorkout: keepScreenAwakeDuringWorkout,
            showsHomeOverview: showsHomeOverview,
            showsRecentWorkouts: showsRecentWorkouts
        )
    }
}

private struct BackupMuscleGroupPayload: Codable {
    let id: String
    let name: String
    let sortOrder: Int
    let colorHex: String?

    func makeModel() -> MuscleGroup {
        MuscleGroup(name: name, sortOrder: sortOrder, colorHex: colorHex ?? "#4F7A28")
    }
}

private struct BackupExercisePayload: Codable {
    let id: String
    let muscleGroupID: String?
    let name: String
    let normalizedName: String
    let isCustom: Bool
    let createdAt: Date
    let notes: String
    let isFavorite: Bool
    let exerciseType: ExerciseType
    let preferredWeightUnit: WeightUnit
    let defaultRestSeconds: Int
    let defaultProgressionView: ExerciseProgressionView
    let goalMetric: ExerciseProgressionView?
    let goalTargetValue: Double?
    let goalNotes: String

    func makeModel(muscleGroup: MuscleGroup?) -> Exercise {
        Exercise(
            name: name,
            normalizedName: normalizedName,
            isCustom: isCustom,
            createdAt: createdAt,
            notes: notes,
            isFavorite: isFavorite,
            exerciseType: exerciseType,
            preferredWeightUnit: preferredWeightUnit,
            defaultRestSeconds: defaultRestSeconds,
            defaultProgressionView: defaultProgressionView,
            goalMetric: goalMetric,
            goalTargetValue: goalTargetValue,
            goalNotes: goalNotes,
            muscleGroup: muscleGroup
        )
    }
}

private struct BackupWorkoutPayload: Codable {
    let date: Date
    let startedAt: Date
    let finishedAt: Date?
    let comment: String
    let sets: [BackupWorkoutSetPayload]

    func makeModel() -> Workout {
        Workout(date: date, startedAt: startedAt, finishedAt: finishedAt, comment: comment)
    }
}

private struct BackupBodyMeasurementPayload: Codable {
    let id: String
    let name: String
    let normalizedName: String
    let unitSymbol: String
    let isEnabled: Bool
    let sortOrder: Int
    let createdAt: Date
    let goalDirection: BodyMeasurementGoalDirection?
    let goalTargetValue: Double?
    let goalNotes: String
    let entries: [BackupBodyMeasurementEntryPayload]

    func makeModel() -> BodyMeasurementMetric {
        BodyMeasurementMetric(
            name: name,
            normalizedName: normalizedName,
            unitSymbol: unitSymbol,
            isEnabled: isEnabled,
            sortOrder: sortOrder,
            createdAt: createdAt,
            goalDirection: goalDirection,
            goalTargetValue: goalTargetValue,
            goalNotes: goalNotes
        )
    }
}

private struct BackupBodyMeasurementEntryPayload: Codable {
    let recordedAt: Date
    let value: Double
    let note: String

    func makeModel(metric: BodyMeasurementMetric) -> BodyMeasurementEntry {
        BodyMeasurementEntry(
            recordedAt: recordedAt,
            value: value,
            note: note,
            metric: metric
        )
    }
}

private struct BackupWorkoutSetPayload: Codable {
    let exerciseID: String?
    let exerciseOrder: Int
    let setOrder: Int
    let weight: Double
    let reps: Int
    let comment: String
    let isCompleted: Bool
    let exerciseNameSnapshot: String
    let muscleGroupNameSnapshot: String

    func makeModel(workout: Workout, exercise: Exercise?) -> WorkoutSet {
        WorkoutSet(
            exerciseOrder: exerciseOrder,
            setOrder: setOrder,
            weight: weight,
            reps: reps,
            comment: comment,
            isCompleted: isCompleted,
            exerciseNameSnapshot: exerciseNameSnapshot,
            muscleGroupNameSnapshot: muscleGroupNameSnapshot,
            workout: workout,
            exercise: exercise
        )
    }
}
