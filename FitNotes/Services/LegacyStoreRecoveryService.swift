import Foundation
import SwiftData
import CoreData

struct LegacyStoreRecoveryResult {
    let backupStoreURL: URL
}

enum LegacyStoreRecoveryError: LocalizedError {
    case sourceStoreMissing(URL)
    case recoveryFailed(backupStoreURL: URL?, step: String, underlyingErrorDescription: String)

    var errorDescription: String? {
        switch self {
        case let .sourceStoreMissing(storeURL):
            return "The legacy store file no longer exists at \(storeURL.path)."
        case let .recoveryFailed(backupStoreURL, step, underlyingErrorDescription):
            if let backupStoreURL {
                return """
                Legacy recovery failed while trying to \(step).
                Preserved backup: \(backupStoreURL.path)
                \(underlyingErrorDescription)
                """
            }

            return """
            Legacy recovery failed while trying to \(step).
            \(underlyingErrorDescription)
            """
        }
    }
}

@MainActor
enum LegacyStoreRecoveryService {
    static func recoverStore(at storeURL: URL) throws -> LegacyStoreRecoveryResult {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw LegacyStoreRecoveryError.sourceStoreMissing(storeURL)
        }

        let backupStoreURL = makeBackupStoreURL(for: storeURL)

        do {
            try replaceExistingStoreFiles(at: backupStoreURL)
            try copyStoreFiles(from: storeURL, to: backupStoreURL)
        } catch {
            throw LegacyStoreRecoveryError.recoveryFailed(
                backupStoreURL: backupStoreURL,
                step: "back up the legacy store",
                underlyingErrorDescription: String(describing: error)
            )
        }

        let legacySnapshot: LegacySnapshot
        do {
            legacySnapshot = try loadLegacySnapshot(from: backupStoreURL)
        } catch let error as LegacyStoreRecoveryError {
            switch error {
            case .sourceStoreMissing:
                throw error
            case let .recoveryFailed(existingBackupStoreURL, step, underlyingErrorDescription):
                throw LegacyStoreRecoveryError.recoveryFailed(
                    backupStoreURL: existingBackupStoreURL ?? backupStoreURL,
                    step: step,
                    underlyingErrorDescription: underlyingErrorDescription
                )
            }
        } catch {
            throw LegacyStoreRecoveryError.recoveryFailed(
                backupStoreURL: backupStoreURL,
                step: "read the preserved legacy store",
                underlyingErrorDescription: String(describing: error)
            )
        }

        let recoveredStoreURL = makeRecoveredStoreURL(for: storeURL)
        do {
            try replaceExistingStoreFiles(at: recoveredStoreURL)
            let container = try ModelContainerFactory.makeSharedContainer(storeURL: recoveredStoreURL)
            try importLegacySnapshot(legacySnapshot, into: container.mainContext)

            _ = try ModelContainerFactory.makeSharedContainer(storeURL: recoveredStoreURL)
        } catch let error as LegacyStoreRecoveryError {
            switch error {
            case .sourceStoreMissing:
                throw error
            case let .recoveryFailed(existingBackupStoreURL, step, underlyingErrorDescription):
                throw LegacyStoreRecoveryError.recoveryFailed(
                    backupStoreURL: existingBackupStoreURL ?? backupStoreURL,
                    step: step,
                    underlyingErrorDescription: underlyingErrorDescription
                )
            }
        } catch {
            throw LegacyStoreRecoveryError.recoveryFailed(
                backupStoreURL: backupStoreURL,
                step: "import legacy data into a fresh FitNotes store",
                underlyingErrorDescription: String(describing: error)
            )
        }

        do {
            try replaceExistingStoreFiles(at: storeURL)
            try moveStoreFiles(from: recoveredStoreURL, to: storeURL)
        } catch {
            if !FileManager.default.fileExists(atPath: storeURL.path) {
                try? copyStoreFiles(from: backupStoreURL, to: storeURL)
            }

            throw LegacyStoreRecoveryError.recoveryFailed(
                backupStoreURL: backupStoreURL,
                step: "install the recovered FitNotes store",
                underlyingErrorDescription: String(describing: error)
            )
        }

        return LegacyStoreRecoveryResult(backupStoreURL: backupStoreURL)
    }

    private static func importLegacySnapshot(_ snapshot: LegacySnapshot, into context: ModelContext) throws {
        var muscleGroupsByLegacyID: [URL: MuscleGroup] = [:]
        var uniqueMuscleGroups: [(normalizedName: String, group: MuscleGroup)] = []

        for legacyGroup in snapshot.muscleGroups.sorted(by: { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }) {
            let displayName = sanitizedGroupName(legacyGroup.name)
            let normalizedName = displayName.normalizedCatalogName

            if let existingGroup = uniqueMuscleGroups.first(where: { $0.normalizedName == normalizedName })?.group {
                muscleGroupsByLegacyID[legacyGroup.id] = existingGroup
                continue
            }

            let group = MuscleGroup(name: displayName, sortOrder: uniqueMuscleGroups.count)
            context.insert(group)
            uniqueMuscleGroups.append((normalizedName, group))
            muscleGroupsByLegacyID[legacyGroup.id] = group
        }

        var exercisesByLegacyID: [URL: Exercise] = [:]
        var exercisesByGroupAndName: [String: Exercise] = [:]

        for legacyExercise in snapshot.exercises.sorted(by: { lhs, rhs in
            sanitizedExerciseName(lhs.name).localizedCaseInsensitiveCompare(sanitizedExerciseName(rhs.name)) == .orderedAscending
        }) {
            let group = legacyExercise.muscleGroupID.flatMap { muscleGroupsByLegacyID[$0] }
            let displayName = sanitizedExerciseName(legacyExercise.name)
            let normalizedName = displayName.normalizedExerciseName
            let groupKey = group.map { String(ObjectIdentifier($0).hashValue) } ?? "uncategorized"
            let dedupeKey = "\(groupKey)|\(normalizedName)"

            if let existingExercise = exercisesByGroupAndName[dedupeKey] {
                exercisesByLegacyID[legacyExercise.id] = existingExercise
                continue
            }

            let exercise = Exercise(
                name: displayName,
                normalizedName: normalizedName,
                isCustom: legacyExercise.isCustom,
                muscleGroup: group
            )
            context.insert(exercise)
            exercisesByGroupAndName[dedupeKey] = exercise
            exercisesByLegacyID[legacyExercise.id] = exercise
        }

        let draftWorkouts = snapshot.workouts.filter { $0.finishedAt == nil }
        if draftWorkouts.count > 1 {
            throw LegacyStoreRecoveryError.recoveryFailed(
                backupStoreURL: nil,
                step: "validate draft workout state",
                underlyingErrorDescription: "The legacy store contains more than one in-progress workout."
            )
        }

        for legacyWorkout in snapshot.workouts.sorted(by: { lhs, rhs in
            if lhs.startedAt == rhs.startedAt {
                return lhs.date < rhs.date
            }
            return lhs.startedAt < rhs.startedAt
        }) {
            let normalizedFinishedAt = legacyWorkout.finishedAt
            let normalizedStartedAt: Date
            if let normalizedFinishedAt, legacyWorkout.startedAt > normalizedFinishedAt {
                normalizedStartedAt = normalizedFinishedAt
            } else {
                normalizedStartedAt = legacyWorkout.startedAt
            }

            let normalizedDate: Date
            if legacyWorkout.date > normalizedStartedAt {
                normalizedDate = normalizedStartedAt
            } else if let normalizedFinishedAt, legacyWorkout.date > normalizedFinishedAt {
                normalizedDate = normalizedFinishedAt
            } else {
                normalizedDate = legacyWorkout.date
            }

            let workout = Workout(
                date: normalizedDate,
                startedAt: normalizedStartedAt,
                finishedAt: normalizedFinishedAt
            )
            context.insert(workout)

            let orderedSets = legacyWorkout.sets.sorted(by: { lhs, rhs in
                if lhs.setOrder == rhs.setOrder {
                    return lhs.id.absoluteString < rhs.id.absoluteString
                }
                return lhs.setOrder < rhs.setOrder
            })

            var exerciseOrderByKey: [String: Int] = [:]
            var nextExerciseOrder = 1
            var nextSetOrderByKey: [String: Int] = [:]

            for legacySet in orderedSets {
                guard legacySet.weight > 0, legacySet.reps > 0 else {
                    throw LegacyStoreRecoveryError.recoveryFailed(
                        backupStoreURL: nil,
                        step: "validate imported workout sets",
                        underlyingErrorDescription: "Legacy set values must have positive weight and reps."
                    )
                }

                let exercise = legacySet.exerciseID.flatMap { exercisesByLegacyID[$0] }
                let exerciseKey = legacySet.exerciseID?.absoluteString ?? "deleted-exercise"
                let exerciseOrder = exerciseOrderByKey[exerciseKey] ?? {
                    let order = nextExerciseOrder
                    nextExerciseOrder += 1
                    exerciseOrderByKey[exerciseKey] = order
                    return order
                }()
                let setOrder = (nextSetOrderByKey[exerciseKey] ?? 0) + 1
                nextSetOrderByKey[exerciseKey] = setOrder

                let workoutSet = WorkoutSet(
                    exerciseOrder: exerciseOrder,
                    setOrder: setOrder,
                    weight: legacySet.weight,
                    reps: legacySet.reps,
                    comment: "",
                    isCompleted: normalizedFinishedAt != nil,
                    exerciseNameSnapshot: exercise?.name ?? "Unknown Exercise",
                    muscleGroupNameSnapshot: exercise?.muscleGroup?.name ?? "Uncategorized",
                    workout: workout,
                    exercise: exercise
                )
                context.insert(workoutSet)
            }
        }

        try context.save()
    }

    private static func loadLegacySnapshot(from storeURL: URL) throws -> LegacySnapshot {
        let model = makeLegacyManagedObjectModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let persistentStore: NSPersistentStore

        do {
            persistentStore = try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: [NSReadOnlyPersistentStoreOption: true]
            )
        } catch {
            throw LegacyStoreRecoveryError.recoveryFailed(
                backupStoreURL: storeURL,
                step: "open the preserved legacy store",
                underlyingErrorDescription: String(describing: error)
            )
        }

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        defer {
            // Close the SQLite handle before legacy recovery renames or deletes files.
            context.reset()
            try? coordinator.remove(persistentStore)
        }

        let groupRequest = NSFetchRequest<NSManagedObject>(entityName: "MuscleGroup")
        groupRequest.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ]

        let exerciseRequest = NSFetchRequest<NSManagedObject>(entityName: "Exercise")
        exerciseRequest.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ]

        let workoutRequest = NSFetchRequest<NSManagedObject>(entityName: "Workout")
        workoutRequest.sortDescriptors = [
            NSSortDescriptor(key: "startedAt", ascending: true),
            NSSortDescriptor(key: "date", ascending: true)
        ]

        let setRequest = NSFetchRequest<NSManagedObject>(entityName: "WorkoutSet")
        setRequest.sortDescriptors = [
            NSSortDescriptor(key: "setOrder", ascending: true)
        ]

        let groups = try context.fetch(groupRequest).map { groupObject in
            LegacyMuscleGroup(
                id: groupObject.objectID.uriRepresentation(),
                name: (groupObject.value(forKey: "name") as? String) ?? "",
                sortOrder: Int(groupObject.value(forKey: "sortOrder") as? Int64 ?? 0)
            )
        }

        let exercises = try context.fetch(exerciseRequest).map { exerciseObject in
            LegacyExercise(
                id: exerciseObject.objectID.uriRepresentation(),
                name: (exerciseObject.value(forKey: "name") as? String) ?? "",
                isCustom: exerciseObject.value(forKey: "isCustom") as? Bool ?? true,
                muscleGroupID: (exerciseObject.value(forKey: "muscleGroup") as? NSManagedObject)?.objectID.uriRepresentation()
            )
        }

        let setsByWorkoutID = Dictionary(grouping: try context.fetch(setRequest).map { setObject in
            LegacyWorkoutSet(
                id: setObject.objectID.uriRepresentation(),
                workoutID: ((setObject.value(forKey: "workout") as? NSManagedObject)?.objectID.uriRepresentation()) ?? setObject.objectID.uriRepresentation(),
                exerciseID: (setObject.value(forKey: "exercise") as? NSManagedObject)?.objectID.uriRepresentation(),
                setOrder: Int(setObject.value(forKey: "setOrder") as? Int64 ?? 0),
                weight: setObject.value(forKey: "weight") as? Double ?? 0,
                reps: Int(setObject.value(forKey: "reps") as? Int64 ?? 0)
            )
        }, by: \.workoutID)

        let workouts = try context.fetch(workoutRequest).map { workoutObject in
            let workoutID = workoutObject.objectID.uriRepresentation()
            return LegacyWorkout(
                id: workoutID,
                date: (workoutObject.value(forKey: "date") as? Date) ?? .now,
                startedAt: (workoutObject.value(forKey: "startedAt") as? Date) ?? .now,
                finishedAt: workoutObject.value(forKey: "finishedAt") as? Date,
                sets: setsByWorkoutID[workoutID] ?? []
            )
        }

        return LegacySnapshot(
            muscleGroups: groups,
            exercises: exercises,
            workouts: workouts
        )
    }

    private static func sanitizedGroupName(_ rawName: String) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Uncategorized" : trimmedName
    }

    private static func sanitizedExerciseName(_ rawName: String) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Unknown Exercise" : trimmedName
    }

    private static func makeBackupStoreURL(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(storeURL.lastPathComponent).legacy-backup-\(UUID().uuidString)")
    }

    private static func makeRecoveredStoreURL(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(storeURL.lastPathComponent).recovered-\(UUID().uuidString)")
    }

    private static func copyStoreFiles(from sourceStoreURL: URL, to destinationStoreURL: URL) throws {
        try FileManager.default.createDirectory(
            at: destinationStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        for sourceURL in existingStoreFileURLs(for: sourceStoreURL) {
            let suffix = sourceURL.path.replacingOccurrences(of: sourceStoreURL.path, with: "")
            let destinationURL = URL(fileURLWithPath: destinationStoreURL.path + suffix)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func moveStoreFiles(from sourceStoreURL: URL, to destinationStoreURL: URL) throws {
        try FileManager.default.createDirectory(
            at: destinationStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        for sourceURL in existingStoreFileURLs(for: sourceStoreURL) {
            let suffix = sourceURL.path.replacingOccurrences(of: sourceStoreURL.path, with: "")
            let destinationURL = URL(fileURLWithPath: destinationStoreURL.path + suffix)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func replaceExistingStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        for url in existingStoreFileURLs(for: storeURL) {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private static func existingStoreFileURLs(for storeURL: URL) -> [URL] {
        ["", "-shm", "-wal", "-journal"]
            .map { suffix in
                suffix.isEmpty ? storeURL : URL(fileURLWithPath: storeURL.path + suffix)
            }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func makeLegacyManagedObjectModel() -> NSManagedObjectModel {
        let muscleGroup = NSEntityDescription()
        muscleGroup.name = "MuscleGroup"
        muscleGroup.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let exercise = NSEntityDescription()
        exercise.name = "Exercise"
        exercise.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let workout = NSEntityDescription()
        workout.name = "Workout"
        workout.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let workoutSet = NSEntityDescription()
        workoutSet.name = "WorkoutSet"
        workoutSet.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let muscleGroupName = NSAttributeDescription()
        muscleGroupName.name = "name"
        muscleGroupName.attributeType = .stringAttributeType
        muscleGroupName.isOptional = false

        let muscleGroupSortOrder = NSAttributeDescription()
        muscleGroupSortOrder.name = "sortOrder"
        muscleGroupSortOrder.attributeType = .integer64AttributeType
        muscleGroupSortOrder.isOptional = false

        let exerciseName = NSAttributeDescription()
        exerciseName.name = "name"
        exerciseName.attributeType = .stringAttributeType
        exerciseName.isOptional = false

        let exerciseNormalizedName = NSAttributeDescription()
        exerciseNormalizedName.name = "normalizedName"
        exerciseNormalizedName.attributeType = .stringAttributeType
        exerciseNormalizedName.isOptional = false

        let exerciseIsCustom = NSAttributeDescription()
        exerciseIsCustom.name = "isCustom"
        exerciseIsCustom.attributeType = .booleanAttributeType
        exerciseIsCustom.isOptional = false

        let workoutDate = NSAttributeDescription()
        workoutDate.name = "date"
        workoutDate.attributeType = .dateAttributeType
        workoutDate.isOptional = false

        let workoutStartedAt = NSAttributeDescription()
        workoutStartedAt.name = "startedAt"
        workoutStartedAt.attributeType = .dateAttributeType
        workoutStartedAt.isOptional = false

        let workoutFinishedAt = NSAttributeDescription()
        workoutFinishedAt.name = "finishedAt"
        workoutFinishedAt.attributeType = .dateAttributeType
        workoutFinishedAt.isOptional = true

        let workoutSetSetOrder = NSAttributeDescription()
        workoutSetSetOrder.name = "setOrder"
        workoutSetSetOrder.attributeType = .integer64AttributeType
        workoutSetSetOrder.isOptional = false

        let workoutSetWeight = NSAttributeDescription()
        workoutSetWeight.name = "weight"
        workoutSetWeight.attributeType = .doubleAttributeType
        workoutSetWeight.isOptional = false

        let workoutSetReps = NSAttributeDescription()
        workoutSetReps.name = "reps"
        workoutSetReps.attributeType = .integer64AttributeType
        workoutSetReps.isOptional = false

        let muscleGroupExercises = NSRelationshipDescription()
        muscleGroupExercises.name = "exercises"
        muscleGroupExercises.destinationEntity = exercise
        muscleGroupExercises.minCount = 0
        muscleGroupExercises.maxCount = 0
        muscleGroupExercises.deleteRule = .cascadeDeleteRule
        muscleGroupExercises.isOptional = true

        let exerciseMuscleGroup = NSRelationshipDescription()
        exerciseMuscleGroup.name = "muscleGroup"
        exerciseMuscleGroup.destinationEntity = muscleGroup
        exerciseMuscleGroup.minCount = 0
        exerciseMuscleGroup.maxCount = 1
        exerciseMuscleGroup.deleteRule = .nullifyDeleteRule
        exerciseMuscleGroup.isOptional = true

        let workoutSets = NSRelationshipDescription()
        workoutSets.name = "sets"
        workoutSets.destinationEntity = workoutSet
        workoutSets.minCount = 0
        workoutSets.maxCount = 0
        workoutSets.deleteRule = .cascadeDeleteRule
        workoutSets.isOptional = true

        let workoutSetWorkout = NSRelationshipDescription()
        workoutSetWorkout.name = "workout"
        workoutSetWorkout.destinationEntity = workout
        workoutSetWorkout.minCount = 0
        workoutSetWorkout.maxCount = 1
        workoutSetWorkout.deleteRule = .nullifyDeleteRule
        workoutSetWorkout.isOptional = true

        let exerciseWorkoutSets = NSRelationshipDescription()
        exerciseWorkoutSets.name = "workoutSets"
        exerciseWorkoutSets.destinationEntity = workoutSet
        exerciseWorkoutSets.minCount = 0
        exerciseWorkoutSets.maxCount = 0
        exerciseWorkoutSets.deleteRule = .nullifyDeleteRule
        exerciseWorkoutSets.isOptional = true

        let workoutSetExercise = NSRelationshipDescription()
        workoutSetExercise.name = "exercise"
        workoutSetExercise.destinationEntity = exercise
        workoutSetExercise.minCount = 0
        workoutSetExercise.maxCount = 1
        workoutSetExercise.deleteRule = .nullifyDeleteRule
        workoutSetExercise.isOptional = true

        muscleGroupExercises.inverseRelationship = exerciseMuscleGroup
        exerciseMuscleGroup.inverseRelationship = muscleGroupExercises
        workoutSets.inverseRelationship = workoutSetWorkout
        workoutSetWorkout.inverseRelationship = workoutSets
        exerciseWorkoutSets.inverseRelationship = workoutSetExercise
        workoutSetExercise.inverseRelationship = exerciseWorkoutSets

        muscleGroup.properties = [muscleGroupName, muscleGroupSortOrder, muscleGroupExercises]
        exercise.properties = [exerciseName, exerciseNormalizedName, exerciseIsCustom, exerciseMuscleGroup, exerciseWorkoutSets]
        workout.properties = [workoutDate, workoutStartedAt, workoutFinishedAt, workoutSets]
        workoutSet.properties = [workoutSetSetOrder, workoutSetWeight, workoutSetReps, workoutSetWorkout, workoutSetExercise]

        let model = NSManagedObjectModel()
        model.entities = [muscleGroup, exercise, workout, workoutSet]
        return model
    }
}

private struct LegacySnapshot {
    let muscleGroups: [LegacyMuscleGroup]
    let exercises: [LegacyExercise]
    let workouts: [LegacyWorkout]
}

private struct LegacyMuscleGroup {
    let id: URL
    let name: String
    let sortOrder: Int
}

private struct LegacyExercise {
    let id: URL
    let name: String
    let isCustom: Bool
    let muscleGroupID: URL?
}

private struct LegacyWorkout {
    let id: URL
    let date: Date
    let startedAt: Date
    let finishedAt: Date?
    let sets: [LegacyWorkoutSet]
}

private struct LegacyWorkoutSet {
    let id: URL
    let workoutID: URL
    let exerciseID: URL?
    let setOrder: Int
    let weight: Double
    let reps: Int
}
