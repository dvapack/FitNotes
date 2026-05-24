import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)])
    private var muscleGroups: [MuscleGroup]
    @Query(
        filter: #Predicate<Workout> { workout in
            workout.finishedAt != nil
        },
        sort: [SortDescriptor(\Workout.startedAt, order: .reverse)]
    )
    private var completedWorkouts: [Workout]
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
        completedWorkouts.count
    }

    private var totalTrackedSets: Int {
        muscleGroups
            .flatMap(\.exercises)
            .reduce(0) { partialResult, exercise in
                partialResult + exercise.workoutSets.count
            }
    }

    private var recentWorkouts: [Workout] {
        Array(completedWorkouts.prefix(5))
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

            Section("Last 5 Workouts") {
                if recentWorkouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("Finish a workout to see your latest sessions here.")
                    )
                } else {
                    ForEach(recentWorkouts) { workout in
                        NavigationLink {
                            WorkoutHistoryDetailView(workout: workout)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Text(workoutSummary(for: workout))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if !workout.comment.isEmpty {
                                    Text(workout.comment)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
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

    private func workoutSummary(for workout: Workout) -> String {
        let exerciseCount = Set(workout.sets.compactMap { $0.exercise?.persistentModelID }).count
        return "\(workout.sets.count) sets across \(exerciseCount) exercises"
    }
}

private struct WorkoutDraftDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    let workoutID: PersistentIdentifier

    var body: some View {
        if let workout = modelContext.model(for: workoutID) as? Workout {
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
