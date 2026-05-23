import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)])
    private var muscleGroups: [MuscleGroup]

    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var showingMuscleGroupSheet = false
    @State private var editingMuscleGroup: MuscleGroup?
    @State private var editingExercise: Exercise?
    @State private var exercisePendingDeletion: Exercise?
    @State private var alertMessage: String?

    private var exerciseStore: DefaultExerciseStore {
        DefaultExerciseStore(context: modelContext)
    }

    private var filteredGroups: [MuscleGroup] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty || favoritesOnly else {
            return muscleGroups
        }

        return muscleGroups.compactMap { group in
            let exercises = group.exercises.filter { exercise in
                let matchesQuery = trimmedQuery.isEmpty ||
                    exercise.name.localizedCaseInsensitiveContains(trimmedQuery) ||
                    group.name.localizedCaseInsensitiveContains(trimmedQuery)
                let matchesFavorite = !favoritesOnly || exercise.isFavorite
                return matchesQuery && matchesFavorite
            }

            return exercises.isEmpty ? nil : group
        }
    }

    var body: some View {
        List {
            Section("Browse") {
                Toggle("Favorites Only", isOn: $favoritesOnly)
            }

            ForEach(filteredGroups) { group in
                Section {
                    ForEach(group.exercises
                        .filter { exercise in
                            let matchesQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                                group.name.localizedCaseInsensitiveContains(searchText)
                            let matchesFavorite = !favoritesOnly || exercise.isFavorite
                            return matchesQuery && matchesFavorite
                        }
                        .sorted {
                            if $0.isFavorite == $1.isFavorite {
                                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                            }

                            return $0.isFavorite && !$1.isFavorite
                        }
                    ) { exercise in
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
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                toggleFavorite(exercise)
                            } label: {
                                Label(exercise.isFavorite ? "Unfavorite" : "Favorite", systemImage: exercise.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions {
                            Button("Edit") {
                                editingExercise = exercise
                            }
                            .tint(.blue)

                            Button("Delete", role: .destructive) {
                                exercisePendingDeletion = exercise
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Circle()
                            .fill(Color(hex: group.colorHex ?? "#4F7A28"))
                            .frame(width: 10, height: 10)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingMuscleGroup = group
                    }
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search exercises or categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingMuscleGroupSheet = true
                } label: {
                    Label("Add Category", systemImage: "plus")
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
        .sheet(item: $editingMuscleGroup) { group in
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
        .sheet(item: $editingExercise) { exercise in
            ExerciseEditorSheet(exercise: exercise)
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
                if let exercisePendingDeletion {
                    do {
                        try exerciseStore.deleteExercise(exercisePendingDeletion)
                    } catch {
                        alertMessage = error.localizedDescription
                    }
                    self.exercisePendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Historical sets will keep their saved exercise snapshot, but the exercise will be removed from the library.")
        }
        .alert("Library Update", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func toggleFavorite(_ exercise: Exercise) {
        do {
            try exerciseStore.toggleFavorite(exercise)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct ExerciseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MuscleGroup.sortOrder), SortDescriptor(\MuscleGroup.name)])
    private var muscleGroups: [MuscleGroup]

    let exercise: Exercise

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

    private var exerciseStore: DefaultExerciseStore {
        DefaultExerciseStore(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $selectedMuscleGroupID) {
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
            .navigationTitle("Edit Exercise")
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
            errorMessage = "Choose a category."
            return
        }

        do {
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
                TextField("Category name", text: $name)
                TextField("Color hex", text: $colorHex)
                    .textInputAutocapitalization(.never)

                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(existingGroup == nil ? "New Category" : "Edit Category")
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
            validationMessage = "The category could not be saved."
            return
        }
        dismiss()
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255.0
        let green = Double((int >> 8) & 0xFF) / 255.0
        let blue = Double(int & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
