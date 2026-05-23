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
}
