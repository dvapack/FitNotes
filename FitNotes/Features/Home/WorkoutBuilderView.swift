import SwiftUI
import SwiftData

struct WorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)])
    private var allMuscleGroups: [MuscleGroup]
    @Query(sort: [SortDescriptor(\Exercise.name)])
    private var allExercises: [Exercise]
    @Query(sort: [SortDescriptor(\WorkoutSet.setOrder)])
    private var allWorkoutSets: [WorkoutSet]
    let workout: Workout

    @FocusState private var focusedField: EntryField?
    @State private var selectedMuscleGroupID: PersistentIdentifier?
    @State private var selectedExerciseID: PersistentIdentifier?
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var showingMuscleGroupSheet = false
    @State private var showingExerciseSheet = false
    @State private var showingDiscardConfirmation = false
    @State private var showingFinishEmptyConfirmation = false
    @State private var alertMessage: String?

    private var exerciseStore: DefaultExerciseStore {
        DefaultExerciseStore(context: modelContext)
    }

    private var workoutStore: DefaultWorkoutStore {
        DefaultWorkoutStore(context: modelContext)
    }

    private var muscleGroups: [MuscleGroup] {
        allMuscleGroups
    }

    private var selectedMuscleGroup: MuscleGroup? {
        guard let selectedMuscleGroupID else { return muscleGroups.first }
        return muscleGroups.first { $0.persistentModelID == selectedMuscleGroupID } ?? muscleGroups.first
    }

    private var exercises: [Exercise] {
        guard let selectedMuscleGroup else { return [] }
        let selectedGroupID = selectedMuscleGroup.persistentModelID
        return allExercises.filter { $0.muscleGroup?.persistentModelID == selectedGroupID }
    }

    private var selectedExercise: Exercise? {
        guard let selectedExerciseID else { return exercises.first }
        return exercises.first { $0.persistentModelID == selectedExerciseID } ?? exercises.first
    }

    private var currentMuscleGroupPersistentID: PersistentIdentifier? {
        selectedMuscleGroup?.persistentModelID
    }

    private var currentExercisePersistentID: PersistentIdentifier? {
        selectedExercise?.persistentModelID
    }

    private var currentExerciseSectionTitle: String {
        if let exerciseName = selectedExercise?.name {
            return "\(exerciseName) Sets"
        }

        return "Current Exercise Sets"
    }

    private var currentExerciseSets: [WorkoutSet] {
        guard let selectedExercise else { return [] }
        let workoutID = workout.persistentModelID
        let exerciseID = selectedExercise.persistentModelID
        return allWorkoutSets.filter {
            $0.workout?.persistentModelID == workoutID &&
            $0.exercise?.persistentModelID == exerciseID
        }
    }

    private var allSets: [WorkoutSet] {
        let workoutID = workout.persistentModelID
        return allWorkoutSets.filter { $0.workout?.persistentModelID == workoutID }
    }

    private var groupedSets: [WorkoutExerciseGroup] {
        allSets.groupedByExercise()
    }

    private var canAddSet: Bool {
        selectedExercise != nil && parsedWeight != nil && parsedReps != nil
    }

    private var parsedWeight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    private var parsedReps: Int? {
        Int(repsText)
    }

    var body: some View {
        List {
            Section("Workout") {
                LabeledContent("Started") {
                    Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                }

                LabeledContent("Status") {
                    Text(workout.isInProgress ? "In Progress" : "Finished")
                }
            }

            Section("Select Muscle Group") {
                if muscleGroups.isEmpty {
                    ContentUnavailableView(
                        "No muscle groups available",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Create your first custom muscle group to start adding exercises.")
                    )
                } else {
                    if let currentMuscleGroupID = currentMuscleGroupPersistentID {
                        Picker("Muscle Group", selection: muscleGroupSelection(fallbackID: currentMuscleGroupID)) {
                            ForEach(muscleGroups) { group in
                                Text(group.name).tag(group.persistentModelID)
                            }
                        }
                    }
                }

                Button("Add Custom Muscle Group") {
                    showingMuscleGroupSheet = true
                }
            }

            Section("Select Exercise") {
                if exercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises in this muscle group",
                        systemImage: "dumbbell",
                        description: Text("Create the first custom exercise for this muscle group.")
                    )
                } else {
                    if let currentExerciseID = currentExercisePersistentID {
                        Picker("Exercise", selection: exerciseSelection(fallbackID: currentExerciseID)) {
                            ForEach(exercises) { exercise in
                                Text(exercise.name).tag(exercise.persistentModelID)
                            }
                        }
                    }
                }

                Button("Add Custom Exercise") {
                    showingExerciseSheet = true
                }
            }

            Section("Add Set") {
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
                    .submitLabel(.next)

                TextField("Reps", text: $repsText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .reps)
                    .submitLabel(.done)

                Button("Save Set") {
                    saveSet()
                }
                .disabled(!canAddSet)
            }

            Section(currentExerciseSectionTitle) {
                if currentExerciseSets.isEmpty {
                    ContentUnavailableView(
                        "No sets yet",
                        systemImage: "list.number",
                        description: Text("Add the first set for the selected exercise.")
                    )
                } else {
                    ForEach(currentExerciseSets) { workoutSet in
                        SetRowView(set: workoutSet)
                    }
                    .onDelete(perform: deleteCurrentExerciseSets)
                }
            }

            Section("Workout Summary") {
                if groupedSets.isEmpty {
                    ContentUnavailableView(
                        "Workout is empty",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Add at least one set to see the workout summary.")
                    )
                } else {
                    ForEach(groupedSets) { group in
                        WorkoutExerciseSummaryView(group: group)
                    }
                }
            }
        }
        .navigationTitle("Workout")
        .toolbar {
            if workout.isInProgress {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Discard", role: .destructive) {
                        showingDiscardConfirmation = true
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") {
                        handleFinishTapped()
                    }
                }
            }
        }
        .sheet(isPresented: $showingExerciseSheet) {
            CustomExerciseSheet(
                muscleGroup: selectedMuscleGroup,
                onSave: { name in
                    createExercise(named: name)
                }
            )
        }
        .sheet(isPresented: $showingMuscleGroupSheet) {
            CustomMuscleGroupSheet { name in
                createMuscleGroup(named: name)
            }
        }
        .onAppear {
            syncSelections()
        }
        .onChange(of: muscleGroups.map(\.persistentModelID)) { _, _ in
            syncSelections()
        }
        .onChange(of: exercises.map(\.persistentModelID)) { _, _ in
            syncSelections()
        }
        .alert("Workout Update", isPresented: Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    alertMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Workout", role: .destructive) {
                discardWorkout()
            }
            Button("Keep Workout", role: .cancel) {}
        } message: {
            Text("This removes the current draft and all of its saved sets.")
        }
        .confirmationDialog(
            "Finish empty workout?",
            isPresented: $showingFinishEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Finish Anyway") {
                finishWorkout()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This workout has no saved sets yet.")
        }
        .onSubmit {
            switch focusedField {
            case .weight:
                focusedField = .reps
            case .reps:
                saveSet()
            case .none:
                break
            }
        }
    }

    private func muscleGroupSelection(fallbackID: PersistentIdentifier) -> Binding<PersistentIdentifier> {
        Binding(
            get: { selectedMuscleGroup?.persistentModelID ?? fallbackID },
            set: { newValue in
                selectedMuscleGroupID = newValue
                selectedExerciseID = nil
                syncSelections()
            }
        )
    }

    private func exerciseSelection(fallbackID: PersistentIdentifier) -> Binding<PersistentIdentifier> {
        Binding(
            get: { selectedExercise?.persistentModelID ?? fallbackID },
            set: { newValue in
                selectedExerciseID = newValue
            }
        )
    }

    private func syncSelections() {
        if selectedMuscleGroupID == nil || !muscleGroups.contains(where: { $0.persistentModelID == selectedMuscleGroupID }) {
            selectedMuscleGroupID = muscleGroups.first?.persistentModelID
        }

        if selectedExerciseID == nil || !exercises.contains(where: { $0.persistentModelID == selectedExerciseID }) {
            selectedExerciseID = exercises.first?.persistentModelID
        }
    }

    private func createExercise(named name: String) -> Bool {
        guard let selectedMuscleGroup else {
            alertMessage = "Choose a muscle group before adding a custom exercise."
            return false
        }

        do {
            let exercise = try exerciseStore.createExercise(name: name, in: selectedMuscleGroup, isCustom: true)
            selectedExerciseID = exercise.persistentModelID
            return true
        } catch {
            if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
                alertMessage = description
            } else {
                alertMessage = "The custom exercise could not be saved."
            }
            return false
        }
    }

    private func createMuscleGroup(named name: String) -> Bool {
        do {
            let muscleGroup = try exerciseStore.createMuscleGroup(name: name)
            selectedMuscleGroupID = muscleGroup.persistentModelID
            selectedExerciseID = nil
            syncSelections()
            return true
        } catch {
            if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
                alertMessage = description
            } else {
                alertMessage = "The custom muscle group could not be saved."
            }
            return false
        }
    }

    private func saveSet() {
        guard let selectedExercise else {
            alertMessage = "Choose an exercise before saving a set."
            return
        }

        guard let weight = parsedWeight, weight > 0 else {
            alertMessage = "Enter a valid weight greater than zero."
            return
        }

        guard let reps = parsedReps, reps > 0 else {
            alertMessage = "Enter a valid rep count greater than zero."
            return
        }

        do {
            _ = try workoutStore.addSet(to: workout, exercise: selectedExercise, weight: weight, reps: reps)
            weightText = ""
            repsText = ""
            focusedField = .weight
        } catch {
            alertMessage = "The set could not be saved."
        }
    }

    private func handleFinishTapped() {
        if allSets.isEmpty {
            showingFinishEmptyConfirmation = true
        } else {
            finishWorkout()
        }
    }

    private func finishWorkout() {
        do {
            try workoutStore.finishWorkout(workout)
            dismiss()
        } catch {
            alertMessage = "The workout could not be finished."
        }
    }

    private func discardWorkout() {
        do {
            try workoutStore.deleteWorkout(workout)
            dismiss()
        } catch {
            alertMessage = "The workout could not be discarded."
        }
    }

    private func deleteCurrentExerciseSets(at offsets: IndexSet) {
        do {
            for index in offsets {
                try workoutStore.deleteSet(currentExerciseSets[index])
            }
        } catch {
            alertMessage = "The set could not be deleted."
        }
    }
}

private extension WorkoutBuilderView {
    enum EntryField {
        case weight
        case reps
    }
}

private struct CustomMuscleGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Bool

    @State private var name = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Muscle Group Name") {
                    TextField("e.g. Forearms", text: $name)
                        .textInputAutocapitalization(.words)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Muscle Group")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter a muscle group name."
            return
        }

        validationMessage = nil
        if onSave(trimmedName) {
            dismiss()
        } else {
            validationMessage = "The muscle group could not be saved."
        }
    }
}

private struct SetRowView: View {
    let set: WorkoutSet

    var body: some View {
        HStack {
            Text("Set \(set.setOrder)")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(set.weight.formatted(.number.precision(.fractionLength(0...2)))) kg")
            Text("x")
                .foregroundStyle(.secondary)
            Text("\(set.reps)")
        }
        .font(.subheadline)
    }
}

private struct WorkoutExerciseSummaryView: View {
    let group: WorkoutExerciseGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.headline)
            Text(group.muscleGroupName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(group.sets) { workoutSet in
                SetRowView(set: workoutSet)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CustomExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let muscleGroup: MuscleGroup?
    let onSave: (String) -> Bool

    @State private var name = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Muscle Group") {
                    Text(muscleGroup?.name ?? "No muscle group selected")
                        .foregroundStyle(muscleGroup == nil ? .secondary : .primary)
                }

                Section("Exercise Name") {
                    TextField("e.g. Incline Bench Press", text: $name)
                        .textInputAutocapitalization(.words)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard muscleGroup != nil else {
            validationMessage = "Select a muscle group before creating an exercise."
            return
        }

        guard !trimmedName.isEmpty else {
            validationMessage = "Enter an exercise name."
            return
        }

        validationMessage = nil
        if onSave(trimmedName) {
            dismiss()
        } else {
            validationMessage = "The exercise could not be saved."
        }
    }
}
