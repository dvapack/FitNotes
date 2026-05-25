import XCTest
import SwiftData
import CoreData
@testable import FitNotes

@MainActor
final class FitNotesTests: XCTestCase {
    private enum SimulatedPersistenceError: Error {
        case saveFailed
    }

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

    func testTrainingReviewSnapshotBuildsMonthSummariesAndOverview() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let chest = MuscleGroup(name: "Chest", sortOrder: 0, colorHex: "#AA0000")
        let back = MuscleGroup(name: "Back", sortOrder: 1, colorHex: "#00AA00")
        let bench = Exercise(name: "Bench Press", normalizedName: "bench press", isCustom: false, muscleGroup: chest)
        let row = Exercise(name: "Barbell Row", normalizedName: "barbell row", isCustom: false, muscleGroup: back)

        let may20 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let may21 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 21)))
        let may23 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 23)))

        let workoutOne = Workout(date: may20, startedAt: may20, finishedAt: may20)
        let workoutTwo = Workout(date: may21, startedAt: may21, finishedAt: may21)
        let workoutThree = Workout(date: may23, startedAt: may23, finishedAt: may23)

        context.insert(chest)
        context.insert(back)
        context.insert(bench)
        context.insert(row)
        context.insert(workoutOne)
        context.insert(workoutTwo)
        context.insert(workoutThree)
        context.insert(WorkoutSet(setOrder: 1, weight: 100, reps: 5, workout: workoutOne, exercise: bench))
        context.insert(WorkoutSet(setOrder: 1, weight: 80, reps: 8, workout: workoutTwo, exercise: bench))
        context.insert(WorkoutSet(setOrder: 1, weight: 70, reps: 10, workout: workoutThree, exercise: row))
        try context.save()

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let snapshot = TrainingReviewSnapshot(workouts: workouts, calendar: calendar)
        let overview = snapshot.overview()
        let daySummaries = snapshot.daySummaries(monthAnchor: may20)
        let monthGrid = snapshot.monthGrid(monthAnchor: may20)

        XCTAssertEqual(overview.workoutCount, 3)
        XCTAssertEqual(overview.setCount, 3)
        XCTAssertEqual(overview.activeDays, 3)
        XCTAssertEqual(overview.longestWorkoutDayStreak, 2)
        XCTAssertEqual(overview.currentWorkoutDayStreak, 1)
        XCTAssertEqual(daySummaries.count, 3)
        XCTAssertEqual(monthGrid.count, 42)
        XCTAssertEqual(daySummaries.first?.exerciseSummaries.first?.exerciseName, "Barbell Row")
        XCTAssertTrue(monthGrid.contains(where: { day in
            guard calendar.isDate(day.date, inSameDayAs: may21) else { return false }
            return day.summary?.workoutCount == 1
        }))
    }

    func testTrainingReviewSnapshotFiltersByMuscleGroupAndExercise() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let chest = MuscleGroup(name: "Chest", sortOrder: 0)
        let legs = MuscleGroup(name: "Legs", sortOrder: 1)
        let bench = Exercise(name: "Bench Press", normalizedName: "bench press", isCustom: false, muscleGroup: chest)
        let squat = Exercise(name: "Squat", normalizedName: "squat", isCustom: false, muscleGroup: legs)

        let may20 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let may22 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 22)))
        let chestWorkout = Workout(date: may20, startedAt: may20, finishedAt: may20)
        let legsWorkout = Workout(date: may22, startedAt: may22, finishedAt: may22)

        context.insert(chest)
        context.insert(legs)
        context.insert(bench)
        context.insert(squat)
        context.insert(chestWorkout)
        context.insert(legsWorkout)
        context.insert(WorkoutSet(setOrder: 1, weight: 100, reps: 5, workout: chestWorkout, exercise: bench))
        context.insert(WorkoutSet(setOrder: 1, weight: 140, reps: 5, workout: legsWorkout, exercise: squat))
        try context.save()

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let snapshot = TrainingReviewSnapshot(workouts: workouts, calendar: calendar)
        let chestOnly = snapshot.filteredWorkouts(muscleGroupID: chest.persistentModelID)
        let squatOnly = snapshot.filteredWorkouts(exerciseID: squat.persistentModelID)
        let filteredExercises = snapshot.availableExercises(filteredBy: chest.persistentModelID)

        XCTAssertEqual(chestOnly.count, 1)
        XCTAssertEqual(chestOnly.first?.persistentModelID, chestWorkout.persistentModelID)
        XCTAssertEqual(squatOnly.count, 1)
        XCTAssertEqual(squatOnly.first?.persistentModelID, legsWorkout.persistentModelID)
        XCTAssertEqual(filteredExercises.map(\.name), ["Bench Press"])
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

    func testFinishedWorkoutRejectsSetMutations() throws {
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
        try workoutStore.finishWorkout(workout)

        XCTAssertThrowsError(try workoutStore.updateSet(set, weight: 82.5, reps: 6, comment: "Top set", isCompleted: true)) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .workoutAlreadyFinished)
        }

        XCTAssertThrowsError(try workoutStore.toggleSetCompletion(set)) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .workoutAlreadyFinished)
        }

        XCTAssertThrowsError(try workoutStore.deleteSet(set)) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .workoutAlreadyFinished)
        }

        XCTAssertThrowsError(try workoutStore.moveSets(in: workout, exercise: exercise, fromOffsets: IndexSet(integer: 0), toOffset: 0)) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .workoutAlreadyFinished)
        }

        XCTAssertThrowsError(try workoutStore.reorderExerciseGroups(in: workout, orderedExerciseIDs: [exercise.persistentModelID])) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .workoutAlreadyFinished)
        }
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

    func testModelContainerFactoryRecognizesLegacyUnversionedStoreErrors() {
        XCTAssertTrue(ModelContainerFactoryError.isLegacyUnversionedStoreError(
            "Cannot use staged migration with an unknown coordinator model version."
        ))
        XCTAssertTrue(ModelContainerFactoryError.isLegacyUnversionedStoreError(
            "Cannot use staged migration with an unknown model version."
        ))
        XCTAssertFalse(ModelContainerFactoryError.isLegacyUnversionedStoreError(
            "The persistent store is incompatible."
        ))
    }

    func testModelContainerFactoryErrorExplainsPreVersionedStoreRecoveryForCoreDataMessage() {
        let error = ModelContainerFactoryError.sharedStoreLoadFailed(
            storeURL: URL(fileURLWithPath: "/tmp/FitNotes/default.store"),
            underlyingErrorDescription: "Error Domain=NSCocoaErrorDomain Code=134504 \"Cannot use staged migration with an unknown model version.\""
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

    func testAppBootstrapErrorDescribesLegacyRecoveryFailure() {
        let storeURL = URL(fileURLWithPath: "/tmp/FitNotes/default.store")
        let backupStoreURL = URL(fileURLWithPath: "/tmp/FitNotes/default.store.legacy-backup")
        let error = AppBootstrapError.legacyStoreRecoveryFailed(
            storeURL: storeURL,
            backupStoreURL: backupStoreURL,
            step: "import legacy data into a fresh FitNotes store",
            underlyingErrorDescription: "Legacy set values must have positive weight and reps."
        )

        XCTAssertEqual(error.storeURL, storeURL)
        XCTAssertEqual(error.backupStoreURL, backupStoreURL)
        XCTAssertTrue(error.failureReason.contains("legacy local store"))
        XCTAssertTrue(error.recoverySuggestion.contains(backupStoreURL.path))
        XCTAssertTrue(error.localizedDescription.contains("Preserved backup"))
    }

    func testAppBootstrapErrorDescribesDataPreparationFailure() {
        let storeURL = URL(fileURLWithPath: "/tmp/FitNotes/default.store")
        let error = AppBootstrapError.dataPreparationFailed(
            storeURL: storeURL,
            recoveryContext: .normalStartup,
            step: "repair existing local workout data",
            underlyingErrorDescription: "save failed"
        )

        XCTAssertEqual(error.storeURL, storeURL)
        XCTAssertTrue(error.failureReason.contains("repair existing local workout data"))
        XCTAssertTrue(error.recoverySuggestion.contains("reset local storage"))
        XCTAssertTrue(error.localizedDescription.contains(storeURL.path))
        XCTAssertTrue(error.localizedDescription.contains("save failed"))
    }

    func testAppBootstrapErrorDescribesPostRecoveryPreparationFailure() {
        let storeURL = URL(fileURLWithPath: "/tmp/FitNotes/default.store")
        let backupStoreURL = URL(fileURLWithPath: "/tmp/FitNotes/default.store.legacy-backup")
        let error = AppBootstrapError.dataPreparationFailed(
            storeURL: storeURL,
            recoveryContext: .postLegacyRecovery(backupStoreURL: backupStoreURL),
            step: "repair existing local workout data",
            underlyingErrorDescription: "save failed"
        )

        XCTAssertEqual(error.category, .postRecoveryPreparationFailed)
        XCTAssertEqual(error.backupStoreURL, backupStoreURL)
        XCTAssertTrue(error.failureReason.contains("recovered the legacy local store"))
        XCTAssertTrue(error.recoverySuggestion.contains("delete both"))
        XCTAssertTrue(error.resetConfirmationMessage.contains(backupStoreURL.path))
        XCTAssertTrue(error.localizedDescription.contains("Preserved backup"))
    }

    func testModelContainerFactoryUsesMigrationPlan() {
        let container = ModelContainerFactory.makeInMemoryContainer()

        XCTAssertNotNil(container.migrationPlan)
        XCTAssertTrue(container.migrationPlan == AppMigrationPlan.self)
    }

    func testAppMigrationPlanUsesDistinctSchemaShapesPerStage() {
        let versionModelNames = AppMigrationPlan.schemas.map { schemaType in
            schemaType.models
                .map { String(describing: $0) }
                .sorted()
        }

        for index in 1..<versionModelNames.count {
            XCTAssertNotEqual(
                versionModelNames[index - 1],
                versionModelNames[index],
                "Adjacent schema versions must not describe the same model set, or SwiftData will reject the staged migration plan."
            )
        }
    }

    func testDiskBackedCurrentV3StoreOpensThroughSharedContainer() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        try createVersionedStore(at: storeURL, version: AppSchemaV3.self) { context in
            let group = MuscleGroup(name: "Chest", sortOrder: 0)
            let exercise = Exercise(name: "Bench Press", normalizedName: "bench press", isCustom: false, muscleGroup: group)
            let workout = Workout(date: .now, startedAt: .now, finishedAt: .now)
            let set = WorkoutSet(exerciseOrder: 1, setOrder: 1, weight: 100, reps: 5, workout: workout, exercise: exercise)

            context.insert(group)
            context.insert(exercise)
            context.insert(workout)
            context.insert(set)
        }

        let reopenedContainer = try ModelContainerFactory.makeSharedContainer(storeURL: storeURL)
        let context = ModelContext(reopenedContainer)

        XCTAssertEqual(try context.fetch(FetchDescriptor<MuscleGroup>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSet>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyMeasurementMetric>()).count, 0)
    }

    func testDiskBackedV1StoreMigratesToCurrentSchema() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        try createVersionedStore(at: storeURL, version: AppSchemaV1.self) { context in
            let group = MuscleGroup(name: "Back", sortOrder: 0)
            let exercise = Exercise(name: "Row", normalizedName: "row", isCustom: false, muscleGroup: group)
            let workout = Workout(date: .now, startedAt: .now, finishedAt: .now)
            let set = WorkoutSet(exerciseOrder: 1, setOrder: 1, weight: 70, reps: 10, workout: workout, exercise: exercise)

            context.insert(group)
            context.insert(exercise)
            context.insert(workout)
            context.insert(set)
        }

        let reopenedContainer = try ModelContainerFactory.makeSharedContainer(storeURL: storeURL)
        let context = ModelContext(reopenedContainer)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())

        XCTAssertEqual(exercises.map(\.name), ["Row"])
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(sets.map(\.setOrder), [1])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyMeasurementMetric>()).count, 0)
    }

    func testDiskBackedV2StoreMigratesToCurrentSchema() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        try createVersionedStore(at: storeURL, version: AppSchemaV2.self) { context in
            let settings = AppSettings(unitSystem: .pounds, weightIncrement: 5)
            let group = MuscleGroup(name: "Legs", sortOrder: 0)
            let exercise = Exercise(name: "Squat", normalizedName: "squat", isCustom: false, muscleGroup: group)

            context.insert(settings)
            context.insert(group)
            context.insert(exercise)
        }

        let reopenedContainer = try ModelContainerFactory.makeSharedContainer(storeURL: storeURL)
        let context = ModelContext(reopenedContainer)
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<AppSettings>()).first)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        XCTAssertEqual(settings.unitSystem, .pounds)
        XCTAssertEqual(settings.weightIncrement, 5)
        XCTAssertEqual(exercises.map(\.name), ["Squat"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyMeasurementMetric>()).count, 0)
    }

    func testDiskBackedLegacyUnversionedStoreFailsSharedContainerLoad() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        try createLegacyCoreDataStore(at: storeURL) { context in
            let group = NSEntityDescription.insertNewObject(forEntityName: "MuscleGroup", into: context)
            group.setValue("Chest", forKey: "name")
            group.setValue(0, forKey: "sortOrder")
        }

        XCTAssertThrowsError(try ModelContainerFactory.makeSharedContainer(storeURL: storeURL)) { error in
            guard let factoryError = error as? ModelContainerFactoryError else {
                return XCTFail("Expected ModelContainerFactoryError, got \(type(of: error))")
            }

            switch factoryError {
            case let .sharedStoreLoadFailed(failedStoreURL, description):
                XCTAssertEqual(failedStoreURL, storeURL)
                XCTAssertTrue(ModelContainerFactoryError.isLegacyUnversionedStoreError(description))
                XCTAssertTrue(factoryError.failureReason.contains("before FitNotes started versioning"))
                XCTAssertTrue(factoryError.recoverySuggestion.contains("preserved"))
            }
        }
    }

    func testAppBootstrapLoadSharedStateRecoversLegacyStoreAtTemporaryPath() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        try createLegacyCoreDataStore(at: storeURL) { context in
            let group = NSEntityDescription.insertNewObject(forEntityName: "MuscleGroup", into: context)
            group.setValue("Back", forKey: "name")
            group.setValue(0, forKey: "sortOrder")

            let exercise = NSEntityDescription.insertNewObject(forEntityName: "Exercise", into: context)
            exercise.setValue("Barbell Row", forKey: "name")
            exercise.setValue("barbell row", forKey: "normalizedName")
            exercise.setValue(false, forKey: "isCustom")
            exercise.setValue(group, forKey: "muscleGroup")

            let workout = NSEntityDescription.insertNewObject(forEntityName: "Workout", into: context)
            let startedAt = Date(timeIntervalSinceReferenceDate: 10_000)
            workout.setValue(startedAt, forKey: "date")
            workout.setValue(startedAt, forKey: "startedAt")
            workout.setValue(startedAt.addingTimeInterval(1_800), forKey: "finishedAt")

            let firstSet = NSEntityDescription.insertNewObject(forEntityName: "WorkoutSet", into: context)
            firstSet.setValue(2, forKey: "setOrder")
            firstSet.setValue(80, forKey: "weight")
            firstSet.setValue(8, forKey: "reps")
            firstSet.setValue(workout, forKey: "workout")
            firstSet.setValue(exercise, forKey: "exercise")

            let secondSet = NSEntityDescription.insertNewObject(forEntityName: "WorkoutSet", into: context)
            secondSet.setValue(4, forKey: "setOrder")
            secondSet.setValue(90, forKey: "weight")
            secondSet.setValue(6, forKey: "reps")
            secondSet.setValue(workout, forKey: "workout")
            secondSet.setValue(exercise, forKey: "exercise")
        }

        let state = AppBootstrap.loadSharedState(storeURL: storeURL)

        switch state {
        case let .ready(container):
            let context = ModelContext(container)
            let groups = try context.fetch(FetchDescriptor<MuscleGroup>())
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            let workouts = try context.fetch(FetchDescriptor<Workout>())
            let sets = try context.fetch(FetchDescriptor<WorkoutSet>(sortBy: [
                SortDescriptor(\.exerciseOrder),
                SortDescriptor(\.setOrder)
            ]))
            let settings = try context.fetch(FetchDescriptor<AppSettings>())

            XCTAssertEqual(groups.map(\.name), ["Back"])
            XCTAssertEqual(exercises.map(\.name), ["Barbell Row"])
            XCTAssertEqual(workouts.count, 1)
            XCTAssertEqual(sets.map(\.setOrder), [1, 2])
            XCTAssertEqual(sets.map(\.exerciseOrder), [1, 1])
            XCTAssertTrue(sets.allSatisfy(\.isCompleted))
            XCTAssertEqual(sets.first?.exerciseNameSnapshot, "Barbell Row")
            XCTAssertEqual(sets.first?.muscleGroupNameSnapshot, "Back")
            XCTAssertEqual(settings.count, 1)
        case let .failed(error):
            XCTFail("Expected legacy recovery to succeed, got: \(error.localizedDescription)")
        }
    }

    func testAppBootstrapLegacyRecoveryFailurePreservesOriginalStoreAndBackup() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        try createLegacyCoreDataStore(at: storeURL) { context in
            let group = NSEntityDescription.insertNewObject(forEntityName: "MuscleGroup", into: context)
            group.setValue("Chest", forKey: "name")
            group.setValue(0, forKey: "sortOrder")

            let exercise = NSEntityDescription.insertNewObject(forEntityName: "Exercise", into: context)
            exercise.setValue("Bench Press", forKey: "name")
            exercise.setValue("bench press", forKey: "normalizedName")
            exercise.setValue(false, forKey: "isCustom")
            exercise.setValue(group, forKey: "muscleGroup")

            let workout = NSEntityDescription.insertNewObject(forEntityName: "Workout", into: context)
            let startedAt = Date(timeIntervalSinceReferenceDate: 20_000)
            workout.setValue(startedAt, forKey: "date")
            workout.setValue(startedAt, forKey: "startedAt")
            workout.setValue(startedAt.addingTimeInterval(1_200), forKey: "finishedAt")

            let invalidSet = NSEntityDescription.insertNewObject(forEntityName: "WorkoutSet", into: context)
            invalidSet.setValue(1, forKey: "setOrder")
            invalidSet.setValue(0, forKey: "weight")
            invalidSet.setValue(5, forKey: "reps")
            invalidSet.setValue(workout, forKey: "workout")
            invalidSet.setValue(exercise, forKey: "exercise")
        }

        let state = AppBootstrap.loadSharedState(storeURL: storeURL)

        switch state {
        case .ready:
            XCTFail("Expected invalid legacy recovery to fail.")
        case let .failed(error):
            guard case let .legacyStoreRecoveryFailed(failedStoreURL, backupStoreURL, step, underlyingErrorDescription) = error else {
                return XCTFail("Expected a legacy recovery failure, got \(error).")
            }

            XCTAssertEqual(failedStoreURL, storeURL)
            XCTAssertEqual(step, "validate imported workout sets")
            XCTAssertTrue(underlyingErrorDescription.contains("positive weight and reps"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

            let preservedBackupURL = try XCTUnwrap(backupStoreURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: preservedBackupURL.path))
            XCTAssertTrue(error.recoverySuggestion.contains(preservedBackupURL.path))
        }
    }

    func testAppBootstrapPostRecoveryPreparationFailureKeepsBackupContext() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        try createLegacyCoreDataStore(at: storeURL) { context in
            let group = NSEntityDescription.insertNewObject(forEntityName: "MuscleGroup", into: context)
            group.setValue("Back", forKey: "name")
            group.setValue(0, forKey: "sortOrder")
        }

        AppBootstrap.startupPreparationDiagnosticHook = { recoveryContext in
            guard case .postLegacyRecovery = recoveryContext else {
                return
            }

            struct ExpectedFailure: Error {}
            throw ExpectedFailure()
        }
        defer {
            AppBootstrap.startupPreparationDiagnosticHook = nil
        }

        let state = AppBootstrap.loadSharedState(storeURL: storeURL)

        switch state {
        case .ready:
            XCTFail("Expected post-recovery preparation failure.")
        case let .failed(error):
            guard case let .dataPreparationFailed(failedStoreURL, recoveryContext, step, underlyingErrorDescription) = error else {
                return XCTFail("Expected post-recovery data preparation failure, got \(error).")
            }

            XCTAssertEqual(failedStoreURL, storeURL)
            XCTAssertEqual(step, "finish startup diagnostics")
            XCTAssertTrue(underlyingErrorDescription.contains("ExpectedFailure"))

            guard case let .postLegacyRecovery(backupStoreURL) = recoveryContext else {
                return XCTFail("Expected post-legacy-recovery context.")
            }

            let preservedBackupURL = try XCTUnwrap(backupStoreURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: preservedBackupURL.path))
            XCTAssertTrue(error.recoverySuggestion.contains(preservedBackupURL.path))
        }
    }

    func testAppBootstrapResetStoreFilesCanPreserveBackupByDefault() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        let backupStoreURL = storeURL.deletingLastPathComponent().appendingPathComponent("\(storeURL.lastPathComponent).legacy-backup")

        FileManager.default.createFile(atPath: storeURL.path, contents: Data("active".utf8))
        FileManager.default.createFile(atPath: backupStoreURL.path, contents: Data("backup".utf8))

        let error = AppBootstrapError.legacyStoreRecoveryFailed(
            storeURL: storeURL,
            backupStoreURL: backupStoreURL,
            step: "import legacy data into a fresh FitNotes store",
            underlyingErrorDescription: "failed"
        )

        try AppBootstrap.resetStoreFiles(for: error, includeBackupStore: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupStoreURL.path))
    }

    func testAppBootstrapResetStoreFilesCanDeleteBackupWhenRequested() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        let backupStoreURL = storeURL.deletingLastPathComponent().appendingPathComponent("\(storeURL.lastPathComponent).legacy-backup")

        FileManager.default.createFile(atPath: storeURL.path, contents: Data("active".utf8))
        FileManager.default.createFile(atPath: backupStoreURL.path, contents: Data("backup".utf8))

        let error = AppBootstrapError.legacyStoreRecoveryFailed(
            storeURL: storeURL,
            backupStoreURL: backupStoreURL,
            step: "import legacy data into a fresh FitNotes store",
            underlyingErrorDescription: "failed"
        )

        try AppBootstrap.resetStoreFiles(for: error, includeBackupStore: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupStoreURL.path))
    }

    func testModelContainerFactoryResetStoreFilesRemovesJournalSidecars() throws {
        let storeURL = try makeTemporaryStoreURL(testName: #function)
        let journalURL = URL(fileURLWithPath: storeURL.path + "-journal")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")

        FileManager.default.createFile(atPath: storeURL.path, contents: Data("active".utf8))
        FileManager.default.createFile(atPath: journalURL.path, contents: Data("journal".utf8))
        FileManager.default.createFile(atPath: walURL.path, contents: Data("wal".utf8))
        FileManager.default.createFile(atPath: shmURL.path, contents: Data("shm".utf8))

        try ModelContainerFactory.resetStoreFiles(at: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path))
    }

    func testAppSettingsStoreCreatesSingleSettingsRecord() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = AppSettingsStore(context: context)

        let first = try store.fetchOrCreateSettings()
        let second = try store.fetchOrCreateSettings()
        let savedSettings = try store.fetchSettings()

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(savedSettings.count, 1)
        XCTAssertEqual(savedSettings.first?.unitSystem, .kilograms)
        XCTAssertEqual(savedSettings.first?.calendarWeekStart, .monday)
    }

    func testModelContextPersistenceRollsBackUnsavedChangesWhenSaveFails() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = AppSettings()

        context.insert(settings)
        try context.save()

        let previousUnitSystem = settings.unitSystem
        let previousWeightIncrement = settings.weightIncrement

        XCTAssertThrowsError(try ModelContextPersistence.perform(in: context) {
            settings.unitSystem = .pounds
            settings.weightIncrement = 5
        } revert: {
            settings.unitSystem = previousUnitSystem
            settings.weightIncrement = previousWeightIncrement
        } save: {
            throw SimulatedPersistenceError.saveFailed
        }) { error in
            XCTAssertEqual(error as? SimulatedPersistenceError, .saveFailed)
        }

        XCTAssertEqual(settings.unitSystem, .kilograms)
        XCTAssertEqual(settings.weightIncrement, 2.5)
    }

    func testModelContextPersistenceKeepsChangesWhenSaveSucceeds() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let settings = AppSettings()

        context.insert(settings)
        try context.save()

        try ModelContextPersistence.perform(in: context) {
            settings.unitSystem = .pounds
            settings.weightIncrement = 5
        } save: {
            try context.save()
        }

        let storedSettings = try XCTUnwrap(try context.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertEqual(storedSettings.unitSystem, .pounds)
        XCTAssertEqual(storedSettings.weightIncrement, 5)
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

    func testLegacyDataBackfillCreatesAndRepairsAppSettings() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let backfillService = LegacyDataBackfillService(context: context)

        context.insert(AppSettings())
        let duplicate = AppSettings()
        duplicate.unitSystemRaw = "stones"
        duplicate.weightIncrement = -5
        duplicate.calendarWeekStartRaw = "tuesday"
        duplicate.personalRecordBehaviorRaw = "unsupported"
        duplicate.setCompletionBehaviorRaw = "unknown"
        duplicate.nextSetBehaviorRaw = "unknown"
        context.insert(duplicate)
        try context.save()

        let updatedCount = try backfillService.backfillIfNeeded()
        let settings = try context.fetch(FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)]))

        XCTAssertGreaterThan(updatedCount, 0)
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.unitSystem, .kilograms)
        XCTAssertEqual(settings.first?.weightIncrement, 2.5)
        XCTAssertEqual(settings.first?.calendarWeekStart, .monday)
        XCTAssertEqual(settings.first?.personalRecordBehavior, .includeEstimatedOneRepMax)
        XCTAssertEqual(settings.first?.setCompletionBehavior, .markCompleted)
        XCTAssertEqual(settings.first?.nextSetBehavior, .repeatPreviousValues)
    }

    func testAppSettingsSnapshotConvertsWeightsAndWeekdayOrder() throws {
        let settings = AppSettings(
            unitSystem: .pounds,
            weightIncrement: 5,
            calendarWeekStart: .monday,
            personalRecordBehavior: .actualOnly,
            setCompletionBehavior: .leaveIncomplete,
            nextSetBehavior: .clearFields
        )
        let snapshot = AppSettingsSnapshot(settings: settings)
        let baseCalendar = Calendar(identifier: .gregorian)

        XCTAssertEqual(snapshot.calendar(base: baseCalendar).firstWeekday, 2)
        XCTAssertEqual(snapshot.orderedVeryShortWeekdaySymbols(base: baseCalendar).first, "M")
        XCTAssertEqual(snapshot.displayWeight(fromStoredWeight: 100).rounded(), 220)
        XCTAssertEqual(snapshot.storedWeight(fromDisplayWeight: 220.462_262_18).rounded(), 100)
        XCTAssertTrue(snapshot.formatWeight(100).contains("lb"))
        XCTAssertTrue(snapshot.formatWeight(100).contains("220"))
        XCTAssertTrue(snapshot.formatVolume(500).contains("lb·reps"))
        XCTAssertTrue(snapshot.formatVolume(500).contains("102") || snapshot.formatVolume(500).contains("103"))
        XCTAssertEqual(snapshot.formatIncrement(), "5 lb")
        XCTAssertFalse(snapshot.setCompletionBehavior.completesSetsByDefault)
    }

    func testLegacyDataBackfillClearsInvalidExerciseGoals() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let backfillService = LegacyDataBackfillService(context: context)
        let group = MuscleGroup(name: "Chest", sortOrder: 0, colorHex: "")
        let exercise = Exercise(name: "Bench Press", normalizedName: "bench press", isCustom: false, muscleGroup: group)

        exercise.goalMetricRaw = "unsupported"
        exercise.goalTargetValue = -10
        exercise.goalNotesRaw = nil

        context.insert(group)
        context.insert(exercise)
        try context.save()

        let updatedCount = try backfillService.backfillIfNeeded()

        XCTAssertGreaterThan(updatedCount, 0)
        XCTAssertNil(exercise.goalMetric)
        XCTAssertNil(exercise.goalTargetValue)
        XCTAssertEqual(exercise.goalNotes, "")
        XCTAssertFalse(exercise.hasGoal)
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

    func testDataPortabilityBackupRoundTripRestoresFullAppState() throws {
        let sourceContainer = ModelContainerFactory.makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        let seeder = SeedDataService(context: sourceContext)
        let settingsStore = AppSettingsStore(context: sourceContext)
        let exerciseStore = DefaultExerciseStore(context: sourceContext)
        let workoutStore = DefaultWorkoutStore(context: sourceContext)

        try seeder.seedIfNeeded()
        let settings = try settingsStore.fetchOrCreateSettings()
        settings.unitSystem = .pounds
        settings.weightIncrement = 5
        settings.calendarWeekStart = .sunday
        settings.personalRecordBehavior = .actualOnly
        settings.setCompletionBehavior = .leaveIncomplete
        settings.nextSetBehavior = .clearFields
        settings.showsRestTimer = false
        settings.keepScreenAwakeDuringWorkout = false
        settings.showsHomeOverview = false
        settings.showsRecentWorkouts = false

        let forearms = try exerciseStore.createMuscleGroup(name: "Forearms")
        forearms.colorHex = "#123456"

        let wristCurl = try exerciseStore.createExercise(
            name: "Wrist Curl",
            in: forearms,
            isCustom: true,
            notes: "Forearm focus",
            isFavorite: true,
            exerciseType: .weightReps,
            preferredWeightUnit: .lb,
            defaultRestSeconds: 120
        )
        wristCurl.defaultProgressionView = .totalReps
        wristCurl.goalMetric = .totalReps
        wristCurl.goalTargetValue = 60
        wristCurl.goalNotes = "Build grip endurance"

        let temporaryExercise = try exerciseStore.createExercise(name: "Reverse Curl", in: forearms, isCustom: true)

        let finishedWorkout = try workoutStore.createOrResumeDraftWorkout()
        finishedWorkout.comment = "Finished workout"
        _ = try workoutStore.addSet(
            to: finishedWorkout,
            exercise: wristCurl,
            weight: 25,
            reps: 15,
            comment: "Warm-up",
            isCompleted: true
        )
        try workoutStore.finishWorkout(
            finishedWorkout,
            finishedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )

        let draftWorkout = try workoutStore.createOrResumeDraftWorkout()
        draftWorkout.comment = "Current draft"
        let draftSet = try workoutStore.addSet(
            to: draftWorkout,
            exercise: temporaryExercise,
            weight: 30,
            reps: 10,
            comment: "Keep snapshot",
            isCompleted: false
        )
        try exerciseStore.deleteExercise(temporaryExercise)

        XCTAssertNil(draftSet.exercise)

        try sourceContext.save()
        let backupData = try DataPortabilityService(context: sourceContext).exportBackupData()

        let restoredContainer = ModelContainerFactory.makeInMemoryContainer()
        let restoredContext = ModelContext(restoredContainer)
        let restoreResult = try DataPortabilityService(context: restoredContext).restoreBackup(from: backupData)
        let restoredSettings = try AppSettingsStore(context: restoredContext).fetchSettings().first
        let restoredWorkoutStore = DefaultWorkoutStore(context: restoredContext)
        let restoredExerciseStore = DefaultExerciseStore(context: restoredContext)
        let restoredDraft = try XCTUnwrap(try restoredWorkoutStore.fetchActiveDraftWorkout())
        let restoredDraftSets = try restoredWorkoutStore.fetchSets(for: restoredDraft)
        let restoredHistory = try restoredWorkoutStore.fetchWorkoutHistory()
        let restoredForearms = try XCTUnwrap(try restoredExerciseStore.fetchMuscleGroups().first(where: { $0.name == "Forearms" }))
        let restoredWristCurl = try XCTUnwrap(try restoredExerciseStore.fetchExercises(for: restoredForearms).first(where: { $0.name == "Wrist Curl" }))

        XCTAssertEqual(restoreResult.muscleGroupCount, try restoredContext.fetch(FetchDescriptor<MuscleGroup>()).count)
        XCTAssertEqual(restoreResult.exerciseCount, try restoredContext.fetch(FetchDescriptor<Exercise>()).count)
        XCTAssertEqual(restoreResult.workoutCount, try restoredContext.fetch(FetchDescriptor<Workout>()).count)
        XCTAssertEqual(restoreResult.setCount, try restoredContext.fetch(FetchDescriptor<WorkoutSet>()).count)

        XCTAssertEqual(restoredSettings?.unitSystem, .pounds)
        XCTAssertEqual(restoredSettings?.weightIncrement, 5)
        XCTAssertEqual(restoredSettings?.calendarWeekStart, .sunday)
        XCTAssertEqual(restoredSettings?.personalRecordBehavior, .actualOnly)
        XCTAssertEqual(restoredSettings?.setCompletionBehavior, .leaveIncomplete)
        XCTAssertEqual(restoredSettings?.nextSetBehavior, .clearFields)
        XCTAssertFalse(restoredSettings?.showsRestTimer ?? true)
        XCTAssertFalse(restoredSettings?.keepScreenAwakeDuringWorkout ?? true)
        XCTAssertFalse(restoredSettings?.showsHomeOverview ?? true)
        XCTAssertFalse(restoredSettings?.showsRecentWorkouts ?? true)

        XCTAssertEqual(restoredHistory.count, 1)
        XCTAssertEqual(restoredDraft.comment, "Current draft")
        XCTAssertEqual(restoredDraftSets.count, 1)
        XCTAssertNil(restoredDraftSets.first?.exercise)
        XCTAssertEqual(restoredDraftSets.first?.exerciseNameSnapshot, "Reverse Curl")
        XCTAssertEqual(restoredDraftSets.first?.comment, "Keep snapshot")
        XCTAssertFalse(restoredDraftSets.first?.isCompleted ?? true)

        XCTAssertEqual(restoredForearms.colorHex, "#123456")
        XCTAssertTrue(restoredWristCurl.isFavorite)
        XCTAssertEqual(restoredWristCurl.preferredWeightUnit, .lb)
        XCTAssertEqual(restoredWristCurl.defaultRestSeconds, 120)
        XCTAssertEqual(restoredWristCurl.defaultProgressionView, .totalReps)
        XCTAssertEqual(restoredWristCurl.goalMetric, .totalReps)
        XCTAssertEqual(restoredWristCurl.goalTargetValue, 60)
        XCTAssertEqual(restoredWristCurl.goalNotes, "Build grip endurance")
    }

    func testDataPortabilityExportsWorkoutCSVUsingDisplayUnits() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let settings = try AppSettingsStore(context: context).fetchOrCreateSettings()
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        settings.unitSystem = .pounds
        try seeder.seedIfNeeded()
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        workout.comment = "Upper body"
        _ = try workoutStore.addSet(
            to: workout,
            exercise: exercise,
            weight: 100,
            reps: 5,
            comment: "Top set",
            isCompleted: true
        )
        try workoutStore.finishWorkout(workout, finishedAt: workout.startedAt.addingTimeInterval(3_600))

        let csvData = try DataPortabilityService(context: context).exportWorkoutCSV(
            using: AppSettingsSnapshot(settings: settings)
        )
        let csv = try XCTUnwrap(String(data: csvData, encoding: .utf8))
        let expectedWeight = AppSettingsSnapshot(settings: settings)
            .displayWeight(fromStoredWeight: 100)
            .formatted(.number.precision(.fractionLength(0...2)))

        XCTAssertTrue(csv.contains("Workout Status"))
        XCTAssertTrue(csv.contains("\"Finished\""))
        XCTAssertTrue(csv.contains("Weight Unit"))
        XCTAssertTrue(csv.contains("\"lb\""))
        XCTAssertTrue(csv.contains(expectedWeight))
        XCTAssertTrue(csv.contains("\"Upper body\""))
        XCTAssertTrue(csv.contains("\"Top set\""))
    }

    func testDataPortabilityResetWorkoutsPreservesCatalogAndSettings() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let settingsStore = AppSettingsStore(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let settings = try settingsStore.fetchOrCreateSettings()
        settings.unitSystem = .pounds
        let group = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first)
        let exercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: group).first)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        _ = try workoutStore.addSet(to: workout, exercise: exercise, weight: 80, reps: 8)

        let result = try DataPortabilityService(context: context).resetWorkouts()

        XCTAssertEqual(result.deletedWorkoutCount, 1)
        XCTAssertEqual(result.deletedSetCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSet>()).count, 0)
        XCTAssertFalse(try exerciseStore.fetchMuscleGroups().isEmpty)
        XCTAssertEqual(try settingsStore.fetchSettings().first?.unitSystem, .pounds)
    }

    func testDataPortabilityResetAllDataReseedsDefaults() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let settingsStore = AppSettingsStore(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let settings = try settingsStore.fetchOrCreateSettings()
        settings.unitSystem = .pounds
        let customGroup = try exerciseStore.createMuscleGroup(name: "Forearms")
        _ = try exerciseStore.createExercise(name: "Wrist Curl", in: customGroup, isCustom: true)
        let workout = try workoutStore.createOrResumeDraftWorkout()
        let seededGroup = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first(where: { $0.name == "Chest" }))
        let seededExercise = try XCTUnwrap(try exerciseStore.fetchExercises(for: seededGroup).first)
        _ = try workoutStore.addSet(to: workout, exercise: seededExercise, weight: 60, reps: 12)

        let result = try DataPortabilityService(context: context).resetAllData()
        let groups = try exerciseStore.fetchMuscleGroups()
        let savedSettings = try settingsStore.fetchSettings()

        XCTAssertEqual(result.deletedWorkoutCount, 1)
        XCTAssertEqual(result.deletedSetCount, 1)
        XCTAssertGreaterThanOrEqual(result.deletedExerciseCount, 1)
        XCTAssertGreaterThanOrEqual(result.deletedMuscleGroupCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSet>()).count, 0)
        XCTAssertEqual(groups.count, SeedCatalog.defaultGroups.count)
        XCTAssertFalse(groups.contains(where: { $0.name == "Forearms" }))
        XCTAssertEqual(savedSettings.count, 1)
        XCTAssertEqual(savedSettings.first?.unitSystem, .kilograms)
    }

    func testBodyMeasurementStoreValidatesAndReordersMeasurements() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = BodyMeasurementStore(context: context)

        let bodyWeight = try store.createMeasurement(
            name: "Body Weight",
            unitSymbol: "kg",
            goalDirection: .decrease,
            goalTargetValue: 80
        )
        let waist = try store.createMeasurement(name: "Waist", unitSymbol: "cm")

        XCTAssertThrowsError(try store.createMeasurement(name: "  ", unitSymbol: "kg")) { error in
            XCTAssertEqual(error as? BodyMeasurementStoreError, .emptyMeasurementName)
        }

        XCTAssertThrowsError(try store.createMeasurement(name: "body   weight", unitSymbol: "kg")) { error in
            XCTAssertEqual(error as? BodyMeasurementStoreError, .duplicateMeasurement)
        }

        XCTAssertThrowsError(try store.updateMeasurement(
            waist,
            name: "Waist",
            unitSymbol: "",
            isEnabled: true,
            goalDirection: nil,
            goalTargetValue: nil,
            goalNotes: ""
        )) { error in
            XCTAssertEqual(error as? BodyMeasurementStoreError, .emptyUnit)
        }

        try store.moveMeasurements(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let reordered = try store.fetchMeasurements()

        XCTAssertEqual(bodyWeight.goalDirection, .decrease)
        XCTAssertEqual(bodyWeight.goalTargetValue, 80)
        XCTAssertEqual(reordered.map(\.name), ["Waist", "Body Weight"])
        XCTAssertEqual(reordered.map(\.sortOrder), [0, 1])
    }

    func testBodyTrackingSnapshotBuildsHistoryAndGoalStatus() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let metric = BodyMeasurementMetric(
            name: "Body Weight",
            normalizedName: "body weight",
            unitSymbol: "kg",
            goalDirection: .decrease,
            goalTargetValue: 80
        )

        let may1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let may15 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        let may30 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30)))

        context.insert(metric)
        context.insert(BodyMeasurementEntry(recordedAt: may1, value: 90, metric: metric))
        context.insert(BodyMeasurementEntry(recordedAt: may15, value: 87, metric: metric))
        context.insert(BodyMeasurementEntry(recordedAt: may30, value: 85, metric: metric))
        try context.save()

        let snapshot = BodyTrackingSnapshot(metrics: [metric], calendar: calendar)
        let points = snapshot.progression(for: metric, range: .last30Days, granularity: .week)
        let summary = snapshot.summary(for: metric, range: .last30Days, granularity: .week)
        let goalStatus = try XCTUnwrap(snapshot.goalStatus(for: metric))

        XCTAssertEqual(snapshot.enabledMetricCount, 1)
        XCTAssertEqual(snapshot.totalEntryCount, 3)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(summary.currentValue, 85)
        XCTAssertEqual(summary.changeFromStart, -5)
        XCTAssertFalse(goalStatus.isAchieved)
        XCTAssertEqual(goalStatus.targetValue, 80)
        XCTAssertTrue(goalStatus.statusText.contains("5"))
    }

    func testLegacyDataBackfillRepairsBodyMeasurementDefaults() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let backfillService = LegacyDataBackfillService(context: context)
        let metric = BodyMeasurementMetric(name: " Body Fat ", normalizedName: "", unitSymbol: "   ")
        let entry = BodyMeasurementEntry(value: 18.5, metric: metric)

        metric.goalDirectionRaw = "sideways"
        metric.goalTargetValue = -10
        metric.goalNotesRaw = nil
        entry.noteRaw = nil

        context.insert(metric)
        context.insert(entry)
        try context.save()

        let updatedCount = try backfillService.backfillIfNeeded()

        XCTAssertGreaterThan(updatedCount, 0)
        XCTAssertEqual(metric.normalizedName, "body fat")
        XCTAssertEqual(metric.unitSymbol, "unit")
        XCTAssertNil(metric.goalDirection)
        XCTAssertNil(metric.goalTargetValue)
        XCTAssertEqual(metric.goalNotes, "")
        XCTAssertEqual(entry.note, "")
    }

    func testDataPortabilityBackupRoundTripRestoresBodyMeasurements() throws {
        let sourceContainer = ModelContainerFactory.makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        let store = BodyMeasurementStore(context: sourceContext)

        let metric = try store.createMeasurement(
            name: "Body Weight",
            unitSymbol: "kg",
            goalDirection: .decrease,
            goalTargetValue: 82,
            goalNotes: "Cutting phase"
        )
        _ = try store.addEntry(
            to: metric,
            value: 88.5,
            recordedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            note: "Morning check-in"
        )
        _ = try store.addEntry(
            to: metric,
            value: 86.8,
            recordedAt: Date(timeIntervalSinceReferenceDate: 2_000),
            note: "Post deload"
        )

        let service = DataPortabilityService(context: sourceContext)
        let backupData = try service.exportBackupData()
        let preview = try service.previewBackup(from: backupData)

        let restoredContainer = ModelContainerFactory.makeInMemoryContainer()
        let restoredContext = ModelContext(restoredContainer)
        let restoreResult = try DataPortabilityService(context: restoredContext).restoreBackup(from: backupData)
        let restoredMetric = try XCTUnwrap(try restoredContext.fetch(FetchDescriptor<BodyMeasurementMetric>()).first)
        let restoredEntries = restoredMetric.entries.sorted(using: [KeyPathComparator(\BodyMeasurementEntry.recordedAt)])

        XCTAssertEqual(preview.formatVersion, 2)
        XCTAssertEqual(preview.bodyMeasurementCount, 1)
        XCTAssertEqual(preview.bodyMeasurementEntryCount, 2)
        XCTAssertEqual(restoreResult.bodyMeasurementCount, 1)
        XCTAssertEqual(restoreResult.bodyMeasurementEntryCount, 2)
        XCTAssertEqual(restoredMetric.name, "Body Weight")
        XCTAssertEqual(restoredMetric.goalDirection, .decrease)
        XCTAssertEqual(restoredMetric.goalTargetValue, 82)
        XCTAssertEqual(restoredMetric.goalNotes, "Cutting phase")
        XCTAssertEqual(restoredEntries.map(\.value), [88.5, 86.8])
        XCTAssertEqual(restoredEntries.last?.note, "Post deload")
    }

    private func makeTemporaryStoreURL(testName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitNotesTests-\(testName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("default.store")
    }

    private func createVersionedStore<V: VersionedSchema>(
        at storeURL: URL,
        version: V.Type,
        populate: (ModelContext) throws -> Void
    ) throws {
        let schema = Schema(versionedSchema: version)
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        try populate(context)
        try context.save()
    }

    private func createLegacyCoreDataStore(
        at storeURL: URL,
        populate: (NSManagedObjectContext) throws -> Void
    ) throws {
        let model = makeLegacyManagedObjectModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let persistentStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        defer {
            context.reset()
            try? coordinator.remove(persistentStore)
        }

        try populate(context)
        try context.save()
    }

    private func makeLegacyManagedObjectModel() -> NSManagedObjectModel {
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
