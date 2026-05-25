import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)])
    private var muscleGroups: [MuscleGroup]

    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var showingMuscleGroupSheet = false
    @State private var muscleGroupToEdit: MuscleGroup?
    @State private var muscleGroupToAddExercise: MuscleGroup?
    @State private var exerciseToEdit: Exercise?
    @State private var muscleGroupPendingDeletion: MuscleGroup?
    @State private var exercisePendingDeletion: Exercise?
    @State private var alertMessage: String?

    private var exerciseStore: DefaultExerciseStore {
        DefaultExerciseStore(context: modelContext)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isReorderingEnabled: Bool {
        trimmedSearchText.isEmpty && !favoritesOnly
    }

    private var filteredGroups: [MuscleGroup] {
        guard !trimmedSearchText.isEmpty || favoritesOnly else {
            return muscleGroups
        }

        return muscleGroups.filter { group in
            filteredExercises(in: group).isEmpty == false
        }
    }

    var body: some View {
        List {
            Section("Browse") {
                Toggle("Favorites Only", isOn: $favoritesOnly)
            }

            if filteredGroups.isEmpty {
                ContentUnavailableView(
                    trimmedSearchText.isEmpty ? "No muscle groups yet" : "No matching exercises",
                    systemImage: "books.vertical",
                    description: Text(trimmedSearchText.isEmpty ? "Add a muscle group to start building your library." : "Try a different search or add a new exercise.")
                )
            } else if isReorderingEnabled {
                ForEach(muscleGroups) { group in
                    muscleGroupSection(for: group)
                }
                .onMove(perform: moveMuscleGroups)
            } else {
                ForEach(filteredGroups) { group in
                    muscleGroupSection(for: group)
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search exercises or muscle groups")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if muscleGroups.count > 1 && isReorderingEnabled {
                    EditButton()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingMuscleGroupSheet = true
                    } label: {
                        Label("Add Muscle Group", systemImage: "square.stack.3d.up.fill")
                    }

                    Button {
                        muscleGroupToAddExercise = muscleGroups.first
                    } label: {
                        Label("Add Exercise", systemImage: "dumbbell.fill")
                    }
                    .disabled(muscleGroups.isEmpty)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingMuscleGroupSheet) {
            MuscleGroupEditorSheet { name, colorHex in
                do {
                    let group = try exerciseStore.createMuscleGroup(name: name)
                    try exerciseStore.updateMuscleGroup(group, name: name, colorHex: colorHex)
                    return true
                } catch {
                    alertMessage = error.localizedDescription
                    return false
                }
            }
        }
        .sheet(item: $muscleGroupToEdit) { group in
            MuscleGroupEditorSheet(existingGroup: group) { name, colorHex in
                do {
                    try exerciseStore.updateMuscleGroup(group, name: name, colorHex: colorHex)
                    return true
                } catch {
                    alertMessage = error.localizedDescription
                    return false
                }
            }
        }
        .sheet(item: $muscleGroupToAddExercise) { group in
            ExerciseEditorSheet(initialMuscleGroup: group)
        }
        .sheet(item: $exerciseToEdit) { exercise in
            ExerciseEditorSheet(exercise: exercise)
        }
        .alert("Delete Muscle Group?", isPresented: Binding(
            get: { muscleGroupPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    muscleGroupPendingDeletion = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                guard let muscleGroupPendingDeletion else { return }
                do {
                    try exerciseStore.deleteMuscleGroup(muscleGroupPendingDeletion)
                } catch {
                    alertMessage = error.localizedDescription
                }
                self.muscleGroupPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting a muscle group also removes its exercises from the library. Historical workout sets keep their saved snapshots.")
        }
        .alert("Delete Exercise?", isPresented: Binding(
            get: { exercisePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    exercisePendingDeletion = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                guard let exercisePendingDeletion else { return }
                do {
                    try exerciseStore.deleteExercise(exercisePendingDeletion)
                } catch {
                    alertMessage = error.localizedDescription
                }
                self.exercisePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Historical sets will keep their saved exercise snapshot, but the exercise will be removed from the library.")
        }
        .alert("Library Update", isPresented: Binding(
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
    }

    @ViewBuilder
    private func muscleGroupSection(for group: MuscleGroup) -> some View {
        Section {
            let exercises = filteredExercises(in: group)
            if exercises.isEmpty {
                Button {
                    muscleGroupToAddExercise = group
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
            } else {
                ForEach(exercises) { exercise in
                    ExerciseRow(
                        exercise: exercise,
                        destination: { ExerciseInsightsView(exercise: exercise) },
                        onToggleFavorite: { toggleFavorite(exercise) },
                        onEdit: { exerciseToEdit = exercise },
                        onDelete: { exercisePendingDeletion = exercise },
                        onAddAnother: { muscleGroupToAddExercise = group }
                    )
                }
            }
        } header: {
            muscleGroupHeader(for: group)
        }
    }

    @ViewBuilder
    private func muscleGroupHeader(for group: MuscleGroup) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                Text("\(group.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(Color(hex: group.colorHex ?? "#4F7A28"))
                .frame(width: 10, height: 10)

            Menu {
                Button {
                    muscleGroupToAddExercise = group
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }

                Button {
                    muscleGroupToEdit = group
                } label: {
                    Label("Edit Muscle Group", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    muscleGroupPendingDeletion = group
                } label: {
                    Label("Delete Muscle Group", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func filteredExercises(in group: MuscleGroup) -> [Exercise] {
        group.exercises
            .filter { exercise in
                let matchesQuery = trimmedSearchText.isEmpty ||
                    exercise.name.localizedCaseInsensitiveContains(trimmedSearchText) ||
                    group.name.localizedCaseInsensitiveContains(trimmedSearchText)
                let matchesFavorite = !favoritesOnly || exercise.isFavorite
                return matchesQuery && matchesFavorite
            }
            .sorted {
                if $0.isFavorite == $1.isFavorite {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                return $0.isFavorite && !$1.isFavorite
            }
    }

    private func toggleFavorite(_ exercise: Exercise) {
        do {
            try exerciseStore.toggleFavorite(exercise)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func moveMuscleGroups(fromOffsets: IndexSet, toOffset: Int) {
        do {
            try exerciseStore.moveMuscleGroups(fromOffsets: fromOffsets, toOffset: toOffset)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct ExerciseRow<Destination: View>: View {
    let exercise: Exercise
    let destination: () -> Destination
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAddAnother: () -> Void

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(exercise.name)
                        .font(.headline)
                    if exercise.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    Text(exercise.exerciseType.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !exercise.notes.isEmpty {
                    Text(exercise.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Rest \(exercise.defaultRestSeconds)s • \(exercise.preferredWeightUnit.title)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onToggleFavorite) {
                Label(exercise.isFavorite ? "Unfavorite" : "Favorite", systemImage: exercise.isFavorite ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .swipeActions {
            Button("Edit", action: onEdit)
                .tint(.blue)

            Button("Delete", role: .destructive, action: onDelete)
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit Exercise", systemImage: "pencil")
            }

            Button(action: onAddAnother) {
                Label("Add Another Exercise", systemImage: "plus")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Exercise", systemImage: "trash")
            }
        }
    }
}

private struct ExerciseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)])
    private var muscleGroups: [MuscleGroup]

    let exercise: Exercise?

    @State private var name: String
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var defaultRestSeconds: Int
    @State private var exerciseType: ExerciseType
    @State private var preferredWeightUnit: WeightUnit
    @State private var progressionView: ExerciseProgressionView
    @State private var selectedMuscleGroupID: PersistentIdentifier?
    @State private var errorMessage: String?

    init(exercise: Exercise) {
        self.exercise = exercise
        _name = State(initialValue: exercise.name)
        _notes = State(initialValue: exercise.notes)
        _isFavorite = State(initialValue: exercise.isFavorite)
        _defaultRestSeconds = State(initialValue: exercise.defaultRestSeconds)
        _exerciseType = State(initialValue: exercise.exerciseType)
        _preferredWeightUnit = State(initialValue: exercise.preferredWeightUnit)
        _progressionView = State(initialValue: exercise.defaultProgressionView)
        _selectedMuscleGroupID = State(initialValue: exercise.muscleGroup?.persistentModelID)
    }

    init(initialMuscleGroup: MuscleGroup?) {
        self.exercise = nil
        _name = State(initialValue: "")
        _notes = State(initialValue: "")
        _isFavorite = State(initialValue: false)
        _defaultRestSeconds = State(initialValue: 90)
        _exerciseType = State(initialValue: .weightReps)
        _preferredWeightUnit = State(initialValue: .kg)
        _progressionView = State(initialValue: .maxWeight)
        _selectedMuscleGroupID = State(initialValue: initialMuscleGroup?.persistentModelID)
    }

    private var exerciseStore: DefaultExerciseStore {
        DefaultExerciseStore(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Picker("Muscle Group", selection: $selectedMuscleGroupID) {
                        ForEach(muscleGroups) { group in
                            Text(group.name).tag(Optional(group.persistentModelID))
                        }
                    }
                    Toggle("Favorite", isOn: $isFavorite)
                }

                Section("Defaults") {
                    Picker("Type", selection: $exerciseType) {
                        ForEach(ExerciseType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    Picker("Weight Unit", selection: $preferredWeightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    Picker("Progression", selection: $progressionView) {
                        ForEach(ExerciseProgressionView.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    Stepper("Rest \(defaultRestSeconds)s", value: $defaultRestSeconds, in: 0...600, step: 15)
                }

                Section("Notes") {
                    TextField("Exercise notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .alert("Unable to save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let group = muscleGroups.first(where: { $0.persistentModelID == selectedMuscleGroupID }) else {
            errorMessage = "Choose a muscle group."
            return
        }

        do {
            if let exercise {
                try exerciseStore.updateExercise(
                    exercise,
                    name: name,
                    muscleGroup: group,
                    notes: notes,
                    isFavorite: isFavorite,
                    exerciseType: exerciseType,
                    preferredWeightUnit: preferredWeightUnit,
                    defaultRestSeconds: defaultRestSeconds,
                    defaultProgressionView: progressionView
                )
            } else {
                let newExercise = try exerciseStore.createExercise(
                    name: name,
                    in: group,
                    isCustom: true,
                    notes: notes,
                    isFavorite: isFavorite,
                    exerciseType: exerciseType,
                    preferredWeightUnit: preferredWeightUnit,
                    defaultRestSeconds: defaultRestSeconds
                )
                try exerciseStore.updateExercise(
                    newExercise,
                    name: name,
                    muscleGroup: group,
                    notes: notes,
                    isFavorite: isFavorite,
                    exerciseType: exerciseType,
                    preferredWeightUnit: preferredWeightUnit,
                    defaultRestSeconds: defaultRestSeconds,
                    defaultProgressionView: progressionView
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MuscleGroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingGroup: MuscleGroup?
    let onSave: (String, String) -> Bool

    @State private var name: String
    @State private var colorHex: String
    @State private var validationMessage: String?

    init(existingGroup: MuscleGroup? = nil, onSave: @escaping (String, String) -> Bool) {
        self.existingGroup = existingGroup
        self.onSave = onSave
        _name = State(initialValue: existingGroup?.name ?? "")
        _colorHex = State(initialValue: existingGroup?.colorHex ?? "#4F7A28")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Muscle group name", text: $name)
                TextField("Color hex", text: $colorHex)
                    .textInputAutocapitalization(.never)

                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(existingGroup == nil ? "New Muscle Group" : "Edit Muscle Group")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        validationMessage = nil
        guard onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), colorHex.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            validationMessage = "The muscle group could not be saved."
            return
        }
        dismiss()
    }
}
