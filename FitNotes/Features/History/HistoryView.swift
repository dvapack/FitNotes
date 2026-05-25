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
    @State private var errorMessage: String?

    private var totalSets: Int {
        workouts.reduce(0) { $0 + $1.sets.count }
    }

    private var workoutStore: DefaultWorkoutStore {
        DefaultWorkoutStore(context: modelContext)
    }

    var body: some View {
        TrainingReviewContentView(workouts: workouts) { workout in
            workoutPendingDeletion = workout
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
        .alert("Unable to delete workout", isPresented: Binding(
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

    private func confirmDeleteWorkout() {
        guard let workoutPendingDeletion else { return }

        do {
            try workoutStore.deleteWorkout(workoutPendingDeletion)
            self.workoutPendingDeletion = nil
        } catch {
            self.workoutPendingDeletion = nil
            errorMessage = "The workout could not be deleted right now."
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(ModelContainerFactory.makeInMemoryContainer())
}
