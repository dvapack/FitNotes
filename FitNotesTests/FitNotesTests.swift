import XCTest
import SwiftData
@testable import FitNotes

@MainActor
final class FitNotesTests: XCTestCase {
    func testSeedingCreatesDefaultGroupsOnlyOnce() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)

        try seeder.seedIfNeeded()
        try seeder.seedIfNeeded()

        let groups = try context.fetch(FetchDescriptor<MuscleGroup>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(groups.count, SeedCatalog.defaultGroups.count)
        XCTAssertEqual(groups.first?.name, "Chest")
    }

    func testExerciseStoreReadsSeededCatalog() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let groups = try store.fetchMuscleGroups()

        XCTAssertFalse(groups.isEmpty)
        XCTAssertEqual(groups.map(\.name), SeedCatalog.defaultGroups.map(\.name))
    }

    func testSeededCatalogUsesRicherExerciseDefaults() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let chest = try XCTUnwrap(try store.fetchMuscleGroups().first(where: { $0.name == "Chest" }))
        let bench = try XCTUnwrap(try store.fetchExercises(for: chest).first(where: { $0.name == "Bench Press" }))

        XCTAssertEqual(chest.colorHex, "#4F7A28")
        XCTAssertEqual(bench.normalizedName, "bench press")
        XCTAssertEqual(bench.notes, "")
        XCTAssertFalse(bench.isFavorite)
        XCTAssertEqual(bench.exerciseType, .weightReps)
        XCTAssertEqual(bench.preferredWeightUnit, .kg)
        XCTAssertEqual(bench.defaultRestSeconds, 90)
        XCTAssertEqual(bench.defaultProgressionView, .maxWeight)
    }

    func testCreateOrResumeDraftReturnsSingleActiveWorkout() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = DefaultWorkoutStore(context: context)

        let firstDraft = try store.createOrResumeDraftWorkout()
        let secondDraft = try store.createOrResumeDraftWorkout()
        let drafts = try context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.finishedAt == nil
            }
        ))

        XCTAssertEqual(firstDraft.persistentModelID, secondDraft.persistentModelID)
        XCTAssertEqual(drafts.count, 1)
    }

    func testDraftPersistsAcrossStoreInstances() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let firstContext = ModelContext(container)
        let secondContext = ModelContext(container)
        let firstStore = DefaultWorkoutStore(context: firstContext)
        let secondStore = DefaultWorkoutStore(context: secondContext)

        let createdDraft = try firstStore.createOrResumeDraftWorkout()
        let resumedDraft = try secondStore.createOrResumeDraftWorkout()

        XCTAssertEqual(createdDraft.persistentModelID, resumedDraft.persistentModelID)
    }

    func testFinishingWorkoutClearsDraftState() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = DefaultWorkoutStore(context: context)

        let draft = try store.createOrResumeDraftWorkout()
        try store.finishWorkout(draft)

        XCTAssertNotNil(draft.finishedAt)
        XCTAssertNil(try store.fetchActiveDraftWorkout())
        XCTAssertEqual(try store.fetchWorkoutHistory().count, 1)
    }

    func testDeletingWorkoutRemovesDraftAndSets() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        _ = try workoutStore.addSet(to: workout, exercise: exercise, weight: 60, reps: 10)

        try workoutStore.deleteWorkout(workout)

        XCTAssertNil(try workoutStore.fetchActiveDraftWorkout())
        XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSet>()).count, 0)
    }

    func testDeletingSetRemovesOnlyThatSet() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        let firstSet = try workoutStore.addSet(to: workout, exercise: exercise, weight: 60, reps: 10)
        _ = try workoutStore.addSet(to: workout, exercise: exercise, weight: 62.5, reps: 8)

        try workoutStore.deleteSet(firstSet)

        let remainingSets = try workoutStore.fetchSets(for: workout, exercise: exercise)
        XCTAssertEqual(remainingSets.count, 1)
        XCTAssertEqual(remainingSets.first?.weight, 62.5)
    }

    func testCreateExerciseDeduplicatesNormalizedNameWithinGroup() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try store.fetchMuscleGroups().first)
        let firstExercise = try store.createExercise(name: "Cable Fly", in: group, isCustom: true)
        let secondExercise = try store.createExercise(name: "  cable   fly ", in: group, isCustom: true)
        let exercises = try store.fetchExercises(for: group)

        XCTAssertEqual(firstExercise.persistentModelID, secondExercise.persistentModelID)
        XCTAssertEqual(exercises.filter { $0.normalizedName == "cable fly" }.count, 1)
    }

    func testCreateMuscleGroupDeduplicatesNormalizedName() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let firstGroup = try store.createMuscleGroup(name: "Forearms")
        let secondGroup = try store.createMuscleGroup(name: "  forearms  ")
        let groups = try store.fetchMuscleGroups()

        XCTAssertEqual(firstGroup.persistentModelID, secondGroup.persistentModelID)
        XCTAssertEqual(groups.filter { $0.name.normalizedCatalogName == "forearms" }.count, 1)
    }

    func testMoveMuscleGroupsReordersSortOrder() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let originalGroups = try store.fetchMuscleGroups()
        XCTAssertGreaterThanOrEqual(originalGroups.count, 3)

        try store.moveMuscleGroups(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        let reorderedGroups = try store.fetchMuscleGroups()
        XCTAssertEqual(reorderedGroups.prefix(3).map(\.name), Array(originalGroups[1...3].map(\.name)))
        XCTAssertEqual(reorderedGroups[3].name, originalGroups[0].name)
        XCTAssertEqual(reorderedGroups.map(\.sortOrder), Array(0..<reorderedGroups.count))
    }

    func testAddSetIncrementsSetOrderPerExercise() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()

        let firstSet = try workoutStore.addSet(to: workout, exercise: exercise, weight: 80, reps: 8)
        let secondSet = try workoutStore.addSet(to: workout, exercise: exercise, weight: 82.5, reps: 6)
        let storedSets = try workoutStore.fetchSets(for: workout, exercise: exercise)

        XCTAssertEqual(firstSet.setOrder, 1)
        XCTAssertEqual(secondSet.setOrder, 2)
        XCTAssertEqual(storedSets.map(\.setOrder), [1, 2])
    }

    func testFinishedWorkoutAppearsInHistoryWithSavedSets() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()

        _ = try workoutStore.addSet(to: workout, exercise: exercise, weight: 100, reps: 5)
        try workoutStore.finishWorkout(workout)

        let history = try workoutStore.fetchWorkoutHistory()
        let finishedWorkout = try XCTUnwrap(history.first)

        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(finishedWorkout.isInProgress)
        XCTAssertEqual(try workoutStore.fetchSets(for: finishedWorkout).count, 1)
    }

    func testDeletingFinishedWorkoutRemovesItFromHistory() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        _ = try workoutStore.addSet(to: workout, exercise: exercise, weight: 100, reps: 5)
        try workoutStore.finishWorkout(workout)

        try workoutStore.deleteWorkout(workout)

        XCTAssertTrue(try workoutStore.fetchWorkoutHistory().isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSet>()).count, 0)
    }

    func testCreateExerciseRejectsBlankNames() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try store.fetchMuscleGroups().first)

        XCTAssertThrowsError(try store.createExercise(name: "   ", in: group, isCustom: true)) { error in
            XCTAssertEqual(error as? ExerciseStoreError, .emptyExerciseName)
        }
    }

    func testCreateMuscleGroupRejectsBlankNames() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = DefaultExerciseStore(context: context)

        XCTAssertThrowsError(try store.createMuscleGroup(name: "   ")) { error in
            XCTAssertEqual(error as? ExerciseStoreError, .emptyMuscleGroupName)
        }
    }

    func testAddSetRejectsInvalidWeightAndReps() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()

        XCTAssertThrowsError(try workoutStore.addSet(to: workout, exercise: exercise, weight: 0, reps: 5)) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .invalidWeight)
        }

        XCTAssertThrowsError(try workoutStore.addSet(to: workout, exercise: exercise, weight: 20, reps: 0)) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .invalidReps)
        }
    }

    func testImportPreviewSummarizesValidAndSkippedRows() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let importer = FitNotesCSVImporter(context: context)
        let csv = """
        Date,Exercise,Category,Weight,Weight Unit,Reps
        2026-05-20,Bench Press,Chest,100,kg,5
        2026-05-20,Incline Bench Press,Chest,80,kgs,8
        2026-05-20,Curl,Biceps,20,lb,12
        ,Missing Date,Chest,40,kg,10
        """

        let preview = try importer.previewImport(from: Data(csv.utf8))

        XCTAssertEqual(preview.workoutCount, 1)
        XCTAssertEqual(preview.exerciseCount, 2)
        XCTAssertEqual(preview.rows.count, 2)
        XCTAssertEqual(preview.skippedRowCount, 2)
    }

    func testImportPreviewPersistsWorkoutsSetsAndCustomCatalogEntries() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let importer = FitNotesCSVImporter(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)
        let csv = """
        Date,Exercise,Category,Weight,Weight Unit,Reps
        2026-05-20,Wrist Curl,Forearms,15,kg,10
        2026-05-20,Wrist Curl,Forearms,17.5,kg,8
        2026-05-21,Bench Press,Chest,100,kg,5
        """

        try seeder.seedIfNeeded()
        let preview = try importer.previewImport(from: Data(csv.utf8))
        let result = try importer.importPreview(preview)

        XCTAssertEqual(result.importedWorkoutCount, 2)
        XCTAssertEqual(result.importedSetCount, 3)
        XCTAssertEqual(result.skippedRowCount, 0)

        let groups = try exerciseStore.fetchMuscleGroups()
        let forearms = try XCTUnwrap(groups.first(where: { $0.name == "Forearms" }))
        let wristCurl = try XCTUnwrap(try exerciseStore.fetchExercises(for: forearms).first(where: { $0.name == "Wrist Curl" }))
        let history = try workoutStore.fetchWorkoutHistory()
        let forearmsWorkout = try XCTUnwrap(history.first(where: { Calendar.current.isDate($0.date, inSameDayAs: ISO8601DateFormatter().date(from: "2026-05-20T00:00:00Z")!) }))
        let importedSets = try workoutStore.fetchSets(for: forearmsWorkout, exercise: wristCurl)

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(importedSets.map(\.setOrder), [1, 2])
        XCTAssertEqual(importedSets.map(\.reps), [10, 8])
        XCTAssertTrue(importedSets.allSatisfy(\.isCompleted))
        XCTAssertEqual(wristCurl.preferredWeightUnit, .kg)
        XCTAssertEqual(wristCurl.defaultRestSeconds, 90)
        XCTAssertEqual(wristCurl.defaultProgressionView, .maxWeight)
        XCTAssertEqual(forearms.colorHex, "#4F7A28")
    }

    func testStatisticsSnapshotSummarizesPersonalRecords() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let chest = MuscleGroup(name: "Chest", sortOrder: 0)
        let bench = Exercise(name: "Bench Press", normalizedName: "bench press", isCustom: false, muscleGroup: chest)
        let fly = Exercise(name: "Dumbbell Fly", normalizedName: "dumbbell fly", isCustom: false, muscleGroup: chest)

        let workoutOneDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let workoutTwoDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 21)))
        let workoutOne = Workout(date: workoutOneDate, startedAt: workoutOneDate, finishedAt: workoutOneDate)
        let workoutTwo = Workout(date: workoutTwoDate, startedAt: workoutTwoDate, finishedAt: workoutTwoDate)

        context.insert(chest)
        context.insert(bench)
        context.insert(fly)
        context.insert(workoutOne)
        context.insert(workoutTwo)
        context.insert(WorkoutSet(setOrder: 1, weight: 100, reps: 5, workout: workoutOne, exercise: bench))
        context.insert(WorkoutSet(setOrder: 2, weight: 105, reps: 3, workout: workoutOne, exercise: bench))
        context.insert(WorkoutSet(setOrder: 1, weight: 20, reps: 12, workout: workoutTwo, exercise: fly))
        context.insert(WorkoutSet(setOrder: 1, weight: 110, reps: 2, workout: workoutTwo, exercise: bench))
        try context.save()

        let workouts = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt)]))
        let snapshot = WorkoutStatisticsSnapshot(workouts: workouts, calendar: calendar)

        XCTAssertEqual(snapshot.completedWorkoutCount, 2)
        XCTAssertEqual(snapshot.totalSetCount, 4)
        XCTAssertEqual(snapshot.uniqueExerciseCount, 2)
        XCTAssertEqual(snapshot.heaviestWeight, 110)
        XCTAssertEqual(snapshot.personalRecords.first?.exerciseName, "Bench Press")
        XCTAssertEqual(snapshot.personalRecords.first?.maxWeight, 110)
    }

    func testStatisticsSnapshotBuildsProgressionPointsByRangeAndGranularity() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let chest = MuscleGroup(name: "Chest", sortOrder: 0)
        let bench = Exercise(name: "Bench Press", normalizedName: "bench press", isCustom: false, muscleGroup: chest)

        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let thirdDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 22)))
        let firstWorkout = Workout(date: firstDate, startedAt: firstDate, finishedAt: firstDate)
        let secondWorkout = Workout(date: secondDate, startedAt: secondDate, finishedAt: secondDate)
        let thirdWorkout = Workout(date: thirdDate, startedAt: thirdDate, finishedAt: thirdDate)

        context.insert(chest)
        context.insert(bench)
        context.insert(firstWorkout)
        context.insert(secondWorkout)
        context.insert(thirdWorkout)
        context.insert(WorkoutSet(setOrder: 1, weight: 90, reps: 8, workout: firstWorkout, exercise: bench))
        context.insert(WorkoutSet(setOrder: 1, weight: 95, reps: 6, workout: secondWorkout, exercise: bench))
        context.insert(WorkoutSet(setOrder: 2, weight: 100, reps: 5, workout: secondWorkout, exercise: bench))
        context.insert(WorkoutSet(setOrder: 1, weight: 105, reps: 3, workout: thirdWorkout, exercise: bench))
        try context.save()

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let snapshot = WorkoutStatisticsSnapshot(workouts: workouts, calendar: calendar)
        let allTimePoints = snapshot.progression(
            for: bench.persistentModelID,
            metric: .maxWeight,
            range: .allTime,
            granularity: .day
        )
        let recentPoints = snapshot.progression(
            for: bench.persistentModelID,
            metric: .maxWeight,
            range: .last30Days,
            granularity: .day
        )
        let weeklyVolume = snapshot.progression(
            for: bench.persistentModelID,
            metric: .totalVolume,
            range: .last30Days,
            granularity: .week
        )
        let summary = snapshot.progressionSummary(
            for: bench.persistentModelID,
            metric: .maxWeight,
            range: .last30Days,
            granularity: .day
        )

        XCTAssertEqual(allTimePoints.count, 3)
        XCTAssertEqual(allTimePoints.map(\.value), [90, 100, 105])
        XCTAssertEqual(recentPoints.count, 2)
        XCTAssertEqual(recentPoints.map(\.date), [secondDate, thirdDate])
        XCTAssertEqual(weeklyVolume.count, 1)
        XCTAssertEqual(weeklyVolume.first?.value, 1385)
        XCTAssertEqual(summary.bestValue, 105)
        XCTAssertEqual(summary.recentValue, 105)
        XCTAssertEqual(summary.changeFromFirst, 5)
    }

    func testUpdateWorkoutPersistsDateAndComment() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = DefaultWorkoutStore(context: context)
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9)))
        let workout = try store.createOrResumeDraftWorkout()

        try store.updateWorkout(workout, date: date, startedAt: date, finishedAt: nil, comment: "Heavy push day")

        XCTAssertEqual(workout.comment, "Heavy push day")
        XCTAssertEqual(workout.date, date)
        XCTAssertEqual(workout.startedAt, date)
    }

    func testUpdateWorkoutNormalizesOutOfOrderDateAndFinishTime() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = DefaultWorkoutStore(context: context)
        let workout = try store.createOrResumeDraftWorkout()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let finish = Date(timeIntervalSinceReferenceDate: 900)
        let date = Date(timeIntervalSinceReferenceDate: 1_100)

        try store.updateWorkout(workout, date: date, startedAt: start, finishedAt: finish, comment: "  Evening session  ")

        XCTAssertEqual(workout.startedAt, finish)
        XCTAssertEqual(workout.finishedAt, finish)
        XCTAssertEqual(workout.date, finish)
        XCTAssertEqual(workout.comment, "Evening session")
    }

    func testSavedSetsDefaultToCompletedAndStayCompletedAfterEditing() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        let set = try workoutStore.addSet(to: workout, exercise: exercise, weight: 80, reps: 8, comment: "", isCompleted: true)

        XCTAssertTrue(set.isCompleted)

        try workoutStore.updateSet(set, weight: 82.5, reps: 6, comment: "Top set", isCompleted: true)

        XCTAssertEqual(set.weight, 82.5)
        XCTAssertEqual(set.reps, 6)
        XCTAssertEqual(set.comment, "Top set")
        XCTAssertTrue(set.isCompleted)
    }

    func testMoveSetsReordersSetOrder() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        _ = try workoutStore.addSet(to: workout, exercise: exercise, weight: 60, reps: 10, comment: "", isCompleted: true)
        _ = try workoutStore.addSet(to: workout, exercise: exercise, weight: 70, reps: 8, comment: "", isCompleted: true)
        _ = try workoutStore.addSet(to: workout, exercise: exercise, weight: 80, reps: 6, comment: "", isCompleted: true)

        try workoutStore.moveSets(in: workout, exercise: exercise, fromOffsets: IndexSet(integer: 2), toOffset: 0)

        let sets = try workoutStore.fetchSets(for: workout, exercise: exercise)
        XCTAssertEqual(sets.map(\.weight), [80, 60, 70])
        XCTAssertEqual(sets.map(\.setOrder), [1, 2, 3])
    }

    func testReorderExerciseGroupsUpdatesExerciseOrderAcrossWorkout() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let groups = try exerciseStore.fetchMuscleGroups()
        let firstGroup = try XCTUnwrap(groups.first)
        let secondGroup = try XCTUnwrap(groups.dropFirst().first)
        let firstExercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: firstGroup).first)
        let secondExercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: secondGroup).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()

        _ = try workoutStore.addSet(to: workout, exercise: firstExercise, weight: 60, reps: 10, comment: "", isCompleted: true)
        _ = try workoutStore.addSet(to: workout, exercise: secondExercise, weight: 100, reps: 5, comment: "", isCompleted: true)
        _ = try workoutStore.addSet(to: workout, exercise: firstExercise, weight: 70, reps: 8, comment: "", isCompleted: true)

        try workoutStore.reorderExerciseGroups(
            in: workout,
            orderedExerciseIDs: [secondExercise.persistentModelID, firstExercise.persistentModelID]
        )

        let reorderedSets = try workoutStore.fetchSets(for: workout)
        let groupedSets = reorderedSets.groupedByExercise()

        XCTAssertEqual(groupedSets.map(\.title), [secondExercise.name, firstExercise.name])
        XCTAssertEqual(
            reorderedSets.filter { $0.exercise?.persistentModelID == firstExercise.persistentModelID }.map(\.exerciseOrder),
            [2, 2]
        )
        XCTAssertEqual(
            reorderedSets.filter { $0.exercise?.persistentModelID == secondExercise.persistentModelID }.map(\.exerciseOrder),
            [1]
        )
    }

    func testExerciseStoreSearchAndFavorite() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let chest = try XCTUnwrap(try store.fetchMuscleGroups().first(where: { $0.name == "Chest" }))
        let exercise = try store.createExercise(name: "Cable Press", in: chest, isCustom: true)
        try store.toggleFavorite(exercise)

        let searchResults = try store.searchExercises(query: "cable", favoritesOnly: false)
        let favoriteResults = try store.searchExercises(query: "", favoritesOnly: true)

        XCTAssertTrue(searchResults.contains(where: { $0.persistentModelID == exercise.persistentModelID }))
        XCTAssertTrue(favoriteResults.contains(where: { $0.persistentModelID == exercise.persistentModelID }))
    }

    func testUpdateMuscleGroupRejectsDuplicateNormalizedName() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let firstGroup = try store.createMuscleGroup(name: "Forearms")
        let secondGroup = try store.createMuscleGroup(name: "Calves")

        XCTAssertThrowsError(try store.updateMuscleGroup(secondGroup, name: " forearms ", colorHex: "#000000")) { error in
            XCTAssertEqual(error as? ExerciseStoreError, .duplicateMuscleGroup)
        }

        XCTAssertEqual(firstGroup.name, "Forearms")
        XCTAssertEqual(secondGroup.name, "Calves")
    }

    func testUpdateExerciseRejectsDuplicateNormalizedNameWithinGroup() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let store = DefaultExerciseStore(context: context)

        try seeder.seedIfNeeded()
        let chest = try XCTUnwrap(try store.fetchMuscleGroups().first(where: { $0.name == "Chest" }))
        let firstExercise = try store.createExercise(name: "Cable Press", in: chest, isCustom: true)
        let secondExercise = try store.createExercise(name: "Incline Press", in: chest, isCustom: true)

        XCTAssertThrowsError(try store.updateExercise(
            secondExercise,
            name: " cable   press ",
            muscleGroup: chest,
            notes: "",
            isFavorite: false,
            exerciseType: .weightReps,
            preferredWeightUnit: .kg,
            defaultRestSeconds: 90,
            defaultProgressionView: .maxWeight
        )) { error in
            XCTAssertEqual(error as? ExerciseStoreError, .duplicateExercise)
        }

        XCTAssertEqual(firstExercise.name, "Cable Press")
        XCTAssertEqual(secondExercise.name, "Incline Press")
    }

    func testDeleteMuscleGroupCascadesExercisesAndNullifiesWorkoutSets() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        let group = try store.createMuscleGroup(name: "Forearms")
        let exercise = try store.createExercise(name: "Wrist Curl", in: group, isCustom: true)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        let set = try workoutStore.addSet(to: workout, exercise: exercise, weight: 20, reps: 12)

        try store.deleteMuscleGroup(group)

        XCTAssertTrue(try store.fetchMuscleGroups().isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 0)
        XCTAssertNil(set.exercise)
    }

    func testResetStoreFilesRemovesMainStoreAndSidecars() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let storeFiles = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]

        for url in storeFiles {
            FileManager.default.createFile(atPath: url.path(), contents: Data("test".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path()))
        }

        try ModelContainerFactory.resetStoreFiles(at: storeURL)

        for url in storeFiles {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path()))
        }
    }

    func testModelContainerFactoryErrorIncludesStorePath() {
        let storeURL = URL(fileURLWithPath: "/tmp/FitNotes/default.store")
        let error = ModelContainerFactoryError.sharedStoreLoadFailed(
            storeURL: storeURL,
            underlyingErrorDescription: "migration failed"
        )

        XCTAssertTrue(error.localizedDescription.contains(storeURL.path))
        XCTAssertTrue(error.localizedDescription.contains("migration failed"))
    }

    func testModelContainerFactoryErrorExplainsPreVersionedStoreRecovery() {
        let error = ModelContainerFactoryError.sharedStoreLoadFailed(
            storeURL: URL(fileURLWithPath: "/tmp/FitNotes/default.store"),
            underlyingErrorDescription: "SwiftDataError(_error: SwiftData.SwiftDataError.loadIssueModelContainer, _explanation: nil) Cannot use staged migration with an unknown coordinator model version."
        )

        XCTAssertTrue(error.failureReason.contains("before FitNotes started versioning"))
        XCTAssertTrue(error.recoverySuggestion.contains("preserved"))
    }

    func testAppBootstrapErrorWrapsStoreLoadFailureDetails() {
        let storeURL = URL(fileURLWithPath: "/tmp/FitNotes/default.store")
        let wrappedError = AppBootstrapError.storeLoad(.sharedStoreLoadFailed(
            storeURL: storeURL,
            underlyingErrorDescription: "migration failed"
        ))

        XCTAssertEqual(wrappedError.storeURL, storeURL)
        XCTAssertTrue(wrappedError.failureReason.contains("couldn't open"))
        XCTAssertTrue(wrappedError.localizedDescription.contains("migration failed"))
    }

    func testAppBootstrapErrorDescribesDataPreparationFailure() {
        let storeURL = URL(fileURLWithPath: "/tmp/FitNotes/default.store")
        let error = AppBootstrapError.dataPreparationFailed(
            storeURL: storeURL,
            step: "repair existing local workout data",
            underlyingErrorDescription: "save failed"
        )

        XCTAssertEqual(error.storeURL, storeURL)
        XCTAssertTrue(error.failureReason.contains("repair existing local workout data"))
        XCTAssertTrue(error.recoverySuggestion.contains("reset local storage"))
        XCTAssertTrue(error.localizedDescription.contains(storeURL.path))
        XCTAssertTrue(error.localizedDescription.contains("save failed"))
    }

    func testModelContainerFactoryUsesMigrationPlan() {
        let container = ModelContainerFactory.makeInMemoryContainer()

        XCTAssertNotNil(container.migrationPlan)
        XCTAssertTrue(container.migrationPlan == AppMigrationPlan.self)
    }

    func testLegacyDataBackfillPersistsExerciseAndWorkoutDefaults() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let backfillService = LegacyDataBackfillService(context: context)
        let group = MuscleGroup(name: "Chest", sortOrder: 0, colorHex: "")
        let workout = Workout(date: .now, startedAt: .now, finishedAt: .now, comment: "")
        let exercise = Exercise(name: " Bench   Press ", normalizedName: "", isCustom: false, muscleGroup: group)

        exercise.notesRaw = nil
        exercise.exerciseTypeRaw = nil
        exercise.preferredWeightUnitRaw = "stone"
        exercise.defaultRestSeconds = -5
        exercise.defaultProgressionViewRaw = nil
        workout.commentRaw = nil

        context.insert(group)
        context.insert(workout)
        context.insert(exercise)
        try context.save()

        let updatedCount = try backfillService.backfillIfNeeded()

        XCTAssertGreaterThan(updatedCount, 0)
        XCTAssertEqual(group.colorHex, "#4F7A28")
        XCTAssertEqual(exercise.normalizedName, "bench press")
        XCTAssertEqual(exercise.notes, "")
        XCTAssertEqual(exercise.exerciseType, .weightReps)
        XCTAssertEqual(exercise.preferredWeightUnit, .kg)
        XCTAssertEqual(exercise.defaultRestSeconds, 90)
        XCTAssertEqual(exercise.defaultProgressionView, .maxWeight)
        XCTAssertEqual(workout.comment, "")
    }

    func testLegacyDataBackfillRepairsWorkoutSetSnapshotsAndOrdering() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let backfillService = LegacyDataBackfillService(context: context)
        let group = MuscleGroup(name: "Back", sortOrder: 0)
        let exercise = Exercise(name: "Deadlift", normalizedName: "deadlift", isCustom: false, muscleGroup: group)
        let workoutDate = Date()
        let workout = Workout(date: workoutDate, startedAt: workoutDate, finishedAt: workoutDate)
        let firstSet = WorkoutSet(exerciseOrder: 0, setOrder: 4, weight: 140, reps: 5, workout: workout, exercise: exercise)
        let secondSet = WorkoutSet(exerciseOrder: 0, setOrder: 2, weight: 150, reps: 3, workout: workout, exercise: exercise)

        firstSet.commentRaw = nil
        firstSet.exerciseNameSnapshot = nil
        firstSet.muscleGroupNameSnapshot = nil
        secondSet.commentRaw = nil
        secondSet.exerciseNameSnapshot = ""
        secondSet.muscleGroupNameSnapshot = ""

        context.insert(group)
        context.insert(exercise)
        context.insert(workout)
        context.insert(firstSet)
        context.insert(secondSet)
        try context.save()

        let updatedCount = try backfillService.backfillIfNeeded()

        XCTAssertGreaterThan(updatedCount, 0)
        XCTAssertEqual(firstSet.comment, "")
        XCTAssertEqual(secondSet.comment, "")
        XCTAssertEqual(firstSet.exerciseNameSnapshot, "Deadlift")
        XCTAssertEqual(secondSet.exerciseNameSnapshot, "Deadlift")
        XCTAssertEqual(firstSet.muscleGroupNameSnapshot, "Back")
        XCTAssertEqual(secondSet.muscleGroupNameSnapshot, "Back")
        XCTAssertEqual([firstSet.setOrder, secondSet.setOrder].sorted(), [1, 2])
        XCTAssertEqual(firstSet.exerciseOrder, 1)
        XCTAssertEqual(secondSet.exerciseOrder, 1)
    }

}
