import SwiftUI
import SwiftData

struct RoutinesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.name)])
    private var routines: [Routine]

    @State private var selectedRoutine: Routine?
    @State private var showingCreateRoutine = false
    @State private var alertMessage: String?

    private var routineStore: RoutineStore {
        RoutineStore(context: modelContext)
    }

    var body: some View {
        List {
            if routines.isEmpty {
                ContentUnavailableView(
                    "No routines yet",
                    systemImage: "list.clipboard",
                    description: Text("Create a routine to preload exercises and sets into your active workout.")
                )
            } else {
                ForEach(routines) { routine in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(routine.name)
                            .font(.headline)
                        if !routine.notes.isEmpty {
                            Text(routine.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(routine.days.reduce(0) { $0 + $1.exercises.count }) exercises")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRoutine = routine
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            do {
                                try routineStore.deleteRoutine(routine)
                            } catch {
                                alertMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateRoutine = true
                } label: {
                    Label("New Routine", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateRoutine) {
            RoutineEditorView()
        }
        .sheet(item: $selectedRoutine) { routine in
            RoutineDetailSheet(routine: routine)
        }
        .alert("Routine Error", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }
}

private struct RoutineDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let routine: Routine

    private var routineStore: RoutineStore {
        RoutineStore(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(routine.days.sorted { $0.sortOrder < $1.sortOrder }) { day in
                    Section(day.name) {
                        ForEach(day.exercises.sorted { $0.sortOrder < $1.sortOrder }) { routineExercise in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routineExercise.exercise?.name ?? "Deleted Exercise")
                                    .font(.headline)
                                Text(routineExercise.templateSets
                                    .sorted { $0.setOrder < $1.setOrder }
                                    .map { "\($0.weight.formatted(.number.precision(.fractionLength(0...2)))) x \($0.reps)" }
                                    .joined(separator: " • ")
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(routine.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") {
                        _ = try? routineStore.startRoutine(routine)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)])
    private var muscleGroups: [MuscleGroup]

    @State private var name = ""
    @State private var notes = ""
    @State private var dayName = "Day 1"
    @State private var selectedExerciseID: PersistentIdentifier?
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var setCount = 3
    @State private var draftedExercises: [RoutineExerciseDraft] = []
    @State private var errorMessage: String?

    private var routineStore: RoutineStore {
        RoutineStore(context: modelContext)
    }

    private var allExercises: [Exercise] {
        muscleGroups.flatMap(\.exercises).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Routine name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                    TextField("Day name", text: $dayName)
                }

                Section("Add Exercise") {
                    Picker("Exercise", selection: $selectedExerciseID) {
                        ForEach(allExercises) { exercise in
                            Text(exercise.name).tag(Optional(exercise.persistentModelID))
                        }
                    }
                    TextField("Weight", text: $weightText)
                        .keyboardType(.decimalPad)
                    TextField("Reps", text: $repsText)
                        .keyboardType(.numberPad)
                    Stepper("Sets \(setCount)", value: $setCount, in: 1...10)
                    Button("Add to Routine") {
                        appendExercise()
                    }
                }

                Section("Template") {
                    if draftedExercises.isEmpty {
                        Text("Add at least one exercise.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draftedExercises) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.exercise.name)
                                Text("\(item.setCount) sets • \(item.weight.formatted(.number.precision(.fractionLength(0...2)))) x \(item.reps)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            draftedExercises.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .navigationTitle("New Routine")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .alert("Routine Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func appendExercise() {
        guard let exercise = allExercises.first(where: { $0.persistentModelID == selectedExerciseID }),
              let weight = Double(weightText.replacingOccurrences(of: ",", with: ".")),
              let reps = Int(repsText),
              weight > 0,
              reps > 0 else {
            errorMessage = "Choose an exercise and valid set values."
            return
        }

        draftedExercises.append(RoutineExerciseDraft(exercise: exercise, weight: weight, reps: reps, setCount: setCount))
        weightText = ""
        repsText = ""
    }

    private func save() {
        do {
            _ = try routineStore.createRoutine(name: name, notes: notes, dayName: dayName, exercises: draftedExercises)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
