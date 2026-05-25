import SwiftData
import SwiftUI

struct WorkoutHistoryDetailView: View {
    @Query(sort: [SortDescriptor(\AppSettings.createdAt)])
    private var appSettings: [AppSettings]
    let workout: Workout

    private var groupedSets: [WorkoutExerciseGroup] {
        workout.sets.groupedByExercise()
    }

    private var settings: AppSettingsSnapshot {
        AppSettingsSnapshot(settings: appSettings.first)
    }

    var body: some View {
        List {
            Section("Workout") {
                LabeledContent("Started") {
                    Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let finishedAt = workout.finishedAt {
                    LabeledContent("Finished") {
                        Text(finishedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                LabeledContent("Total Sets") {
                    Text("\(workout.sets.count)")
                }

                if !workout.comment.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Comment")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(workout.comment)
                    }
                    .padding(.top, 4)
                }
            }

            Section("Exercises") {
                if groupedSets.isEmpty {
                    ContentUnavailableView(
                        "No sets recorded",
                        systemImage: "list.bullet.rectangle",
                        description: Text("This workout has no saved sets.")
                    )
                } else {
                    ForEach(groupedSets) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            if let exercise = group.exercise {
                                NavigationLink {
                                    ExerciseInsightsView(exercise: exercise)
                                } label: {
                                    exerciseHeader(for: group)
                                }
                            } else {
                                exerciseHeader(for: group)
                            }

                            ForEach(group.sets) { workoutSet in
                                HStack {
                                    Text("Set \(workoutSet.setOrder)")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(settings.formatWeight(workoutSet.weight))
                                    Text("x")
                                        .foregroundStyle(.secondary)
                                    Text("\(workoutSet.reps)")
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Workout Detail")
    }

    @ViewBuilder
    private func exerciseHeader(for group: WorkoutExerciseGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title)
                .font(.headline)
            Text(group.muscleGroupName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
