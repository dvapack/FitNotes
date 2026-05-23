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

    func testRoutineStartCreatesWorkoutSetsFromTemplate() throws {
        let container = ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seeder = SeedDataService(context: context)
        let exerciseStore = DefaultExerciseStore(context: context)
        let routineStore = RoutineStore(context: context)
        let workoutStore = DefaultWorkoutStore(context: context)

        try seeder.seedIfNeeded()
        let chest = try XCTUnwrap(try exerciseStore.fetchMuscleGroups().first(where: { $0.name == "Chest" }))
        let bench = try XCTUnwrap(try exerciseStore.fetchExercises(for: chest).first)
        _ = try routineStore.createRoutine(
            name: "Push Day",
            notes: "Main lift",
            dayName: "Day 1",
            exercises: [RoutineExerciseDraft(exercise: bench, weight: 100, reps: 5, setCount: 3)]
        )

        let routine = try XCTUnwrap(try routineStore.fetchRoutines().first)
        let workout = try routineStore.startRoutine(routine)
        let sets = try workoutStore.fetchSets(for: workout, exercise: bench)

        XCTAssertEqual(workout.comment, "Routine: Push Day")
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.map(\.weight), [100, 100, 100])
        XCTAssertTrue(sets.allSatisfy(\.isCompleted))
    }

    func testWorkoutToolsServiceCalculatesMetrics() {
        let tools = WorkoutToolsService()

        let oneRepMax = tools.estimateOneRepMax(weight: 100, reps: 5)
        let projectedWeight = tools.projectedWorkingWeight(oneRepMax: 120, intensity: 0.75)
        let volume = tools.volume(weight: 80, reps: 8, sets: 4)
        let plates = tools.plateBreakdown(totalWeight: 100)

        XCTAssertNotNil(oneRepMax)
        XCTAssertEqual(projectedWeight, 90)
        XCTAssertEqual(volume, 2560)
        XCTAssertFalse(plates.isEmpty)
    }
}
