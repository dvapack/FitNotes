import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Workout> { workout in
            workout.finishedAt != nil
        },
        sort: [SortDescriptor(\Workout.startedAt, order: .reverse)]
    )
    private var workouts: [Workout]
    @State private var workoutPendingDeletion: Workout?

    private var totalSets: Int {
        workouts.reduce(0) { $0 + $1.sets.count }
    }

    private var workoutStore: DefaultWorkoutStore {
        DefaultWorkoutStore(context: modelContext)
    }

    var body: some View {
        List {
            if workouts.isEmpty {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("Finish a workout to see it here.")
                )
            } else {
                Section("Overview") {
                    LabeledContent("Workouts") {
                        Text("\(workouts.count)")
                    }

                    LabeledContent("Sets") {
                        Text("\(totalSets)")
                    }
                }

                ForEach(workouts) { workout in
                    NavigationLink {
                        WorkoutHistoryDetailView(workout: workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text(workoutSummary(for: workout))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            workoutPendingDeletion = workout
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .alert("Delete Workout?", isPresented: Binding(
            get: { workoutPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    workoutPendingDeletion = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                confirmDeleteWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected workout and all of its saved sets.")
        }
    }

    private func workoutSummary(for workout: Workout) -> String {
        let exerciseCount = Set(workout.sets.compactMap { $0.exercise?.persistentModelID }).count
        return "\(workout.sets.count) sets across \(exerciseCount) exercises"
    }

    private func confirmDeleteWorkout() {
        guard let workoutPendingDeletion else { return }

        do {
            try workoutStore.deleteWorkout(workoutPendingDeletion)
            self.workoutPendingDeletion = nil
        } catch {
            self.workoutPendingDeletion = nil
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(ModelContainerFactory.makeInMemoryContainer())
}
