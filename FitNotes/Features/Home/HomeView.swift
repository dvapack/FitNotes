import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)])
    private var muscleGroups: [MuscleGroup]
    @Query(
        filter: #Predicate<Workout> { workout in
            workout.finishedAt == nil
        },
        sort: [SortDescriptor(\Workout.startedAt, order: .reverse)]
    )
    private var draftWorkouts: [Workout]

    @State private var selectedWorkout: Workout?
    @State private var errorMessage: String?

    private var workoutStore: DefaultWorkoutStore {
        DefaultWorkoutStore(context: modelContext)
    }

    private var completedWorkoutCount: Int {
        (try? workoutStore.fetchWorkoutHistory().count) ?? 0
    }

    private var totalTrackedSets: Int {
        muscleGroups
            .flatMap(\.exercises)
            .reduce(0) { partialResult, exercise in
                partialResult + exercise.workoutSets.count
            }
    }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Completed Workouts") {
                    Text("\(completedWorkoutCount)")
                }

                LabeledContent("Tracked Sets") {
                    Text("\(totalTrackedSets)")
                }
            }

            Section("Workout") {
                if let draft = draftWorkouts.first {
                    NavigationLink(value: draft.persistentModelID) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resume active workout")
                                .font(.headline)
                            Text("Started \(draft.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    startOrResumeWorkout()
                } label: {
                    Label(draftWorkouts.isEmpty ? "New Workout" : "Open Active Workout", systemImage: "plus.circle.fill")
                }
            }

            Section("Muscle Groups") {
                if muscleGroups.isEmpty {
                    ContentUnavailableView(
                        "No muscle groups yet",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Seeded exercises will appear here after the first launch.")
                    )
                } else {
                    ForEach(muscleGroups) { group in
                        HStack {
                            Text(group.name)
                            Spacer()
                            Text("\(group.exercises.count)")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(group.name), \(group.exercises.count) exercises")
                    }
                }
            }
        }
        .navigationTitle("FitNotes")
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutBuilderView(workout: workout)
        }
        .navigationDestination(for: PersistentIdentifier.self) { identifier in
            WorkoutDraftDestinationView(workoutID: identifier)
        }
        .alert("Unable to continue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startOrResumeWorkout() {
        do {
            selectedWorkout = try workoutStore.createOrResumeDraftWorkout()
        } catch {
            errorMessage = "The workout could not be created right now."
        }
    }
}

private struct WorkoutDraftDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    let workoutID: PersistentIdentifier

    var body: some View {
        let workoutStore = DefaultWorkoutStore(context: modelContext)
        if let workout = try? workoutStore.fetchWorkout(id: workoutID) {
            WorkoutBuilderView(workout: workout)
        } else {
            ContentUnavailableView("Workout not found", systemImage: "exclamationmark.circle")
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(ModelContainerFactory.makeInMemoryContainer())
}
