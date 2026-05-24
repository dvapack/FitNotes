import SwiftUI
import SwiftData
import Combine

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
    @State private var setCommentText = ""
    @State private var workoutComment = ""
    @State private var workoutDate = Date()
    @State private var workoutStartedAt = Date()
    @State private var workoutFinishedAt = Date()
    @State private var showingMuscleGroupSheet = false
    @State private var showingExerciseSheet = false
    @State private var showingDiscardConfirmation = false
    @State private var showingFinishEmptyConfirmation = false
    @State private var showingFinishSheet = false
    @State private var editingSet: WorkoutSet?
    @State private var alertMessage: String?
    @State private var currentTime = Date()
    @State private var restTimerRemainingSeconds = 0
    @State private var restTimerTotalSeconds = 0
    @State private var isRestTimerRunning = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

    private var canReorderExerciseGroups: Bool {
        workout.isInProgress &&
        groupedSets.count > 1 &&
        groupedSets.allSatisfy { $0.exercise != nil }
    }

    private var selectedExerciseDefaultRestSeconds: Int {
        max(selectedExercise?.defaultRestSeconds ?? 0, 0)
    }

    private var shouldShowRestTimer: Bool {
        selectedExerciseDefaultRestSeconds > 0 || restTimerRemainingSeconds > 0 || restTimerTotalSeconds > 0
    }

    private var currentWorkoutDuration: TimeInterval {
        max(currentTime.timeIntervalSince(resolvedStartedAt), 0)
    }

    private var pendingFinishDuration: TimeInterval {
        max(workoutFinishedAt.timeIntervalSince(resolvedStartedAt), 0)
    }

    private var restTimerProgress: Double {
        guard restTimerTotalSeconds > 0 else { return 0 }
        let elapsedSeconds = restTimerTotalSeconds - restTimerRemainingSeconds
        return Double(elapsedSeconds) / Double(restTimerTotalSeconds)
    }

    private var restTimerStatusText: String {
        if restTimerRemainingSeconds == 0 {
            return "Ready"
        }

        return isRestTimerRunning ? "Resting" : "Paused"
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
                DatePicker("Workout Day", selection: $workoutDate, displayedComponents: .date)

                DatePicker("Start Time", selection: $workoutStartedAt, displayedComponents: .hourAndMinute)

                LabeledContent("Status") {
                    Text(workout.isInProgress ? "In Progress" : "Finished")
                }

                LabeledContent("Elapsed") {
                    Text(formatDuration(currentWorkoutDuration))
                }

                TextField("Workout comment", text: $workoutComment, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .workoutComment)

                Button("Save Workout Details") {
                    persistWorkoutMetadata()
                }
            }

            Section("Exercise Setup") {
                if muscleGroups.isEmpty {
                    ContentUnavailableView(
                        "No muscle groups available",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Create your first custom muscle group to start adding exercises.")
                    )
                } else if let currentMuscleGroupID = currentMuscleGroupPersistentID {
                    Picker("Muscle Group", selection: muscleGroupSelection(fallbackID: currentMuscleGroupID)) {
                        ForEach(muscleGroups, id: \.persistentModelID) { group in
                            Text(group.name).tag(group.persistentModelID)
                        }
                    }
                }

                if exercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises in this muscle group",
                        systemImage: "dumbbell",
                        description: Text("Create the first custom exercise for this muscle group.")
                    )
                } else if let currentExerciseID = currentExercisePersistentID {
                    Picker("Exercise", selection: exerciseSelection(fallbackID: currentExerciseID)) {
                        ForEach(exercises, id: \.persistentModelID) { exercise in
                            Text(exercise.name).tag(exercise.persistentModelID)
                        }
                    }
                }

                Button("Add Custom Muscle Group") {
                    showingMuscleGroupSheet = true
                }

                Button("Add Custom Exercise") {
                    showingExerciseSheet = true
                }
            }

            restTimerSection
            addSetSection
            currentExerciseSection
            workoutSummarySection
        }
        .navigationTitle("Workout")
        .scrollDismissesKeyboard(.immediately)
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

                if canReorderExerciseGroups {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
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
        .sheet(isPresented: $showingFinishSheet) {
            FinishWorkoutSheet(
                startedAt: resolvedStartedAt,
                finishedAt: $workoutFinishedAt,
                durationText: formatDuration(pendingFinishDuration),
                onFinish: finishWorkout
            )
        }
        .sheet(item: $editingSet) { workoutSet in
            SetEditorSheet(set: workoutSet)
        }
        .onAppear {
            workoutDate = workout.date
            workoutStartedAt = workout.startedAt
            let now = Date()
            currentTime = now
            workoutFinishedAt = max(now, workout.startedAt)
            workoutComment = workout.comment
            syncSelections()
            syncRestTimerForExerciseChange()
        }
        .onChange(of: muscleGroups.map(\.persistentModelID)) { _, _ in
            syncSelections()
        }
        .onChange(of: exercises.map(\.persistentModelID)) { _, _ in
            syncSelections()
            syncRestTimerForExerciseChange()
        }
        .onChange(of: selectedExerciseID) { _, _ in
            syncRestTimerForExerciseChange()
        }
        .onChange(of: workoutDate) { _, _ in
            if workoutFinishedAt < resolvedStartedAt {
                workoutFinishedAt = resolvedStartedAt
            }
        }
        .onChange(of: workoutStartedAt) { _, _ in
            if workoutFinishedAt < resolvedStartedAt {
                workoutFinishedAt = resolvedStartedAt
            }
        }
        .onReceive(clock) { tick in
            currentTime = tick
            guard isRestTimerRunning, restTimerRemainingSeconds > 0 else {
                return
            }

            restTimerRemainingSeconds -= 1
            if restTimerRemainingSeconds == 0 {
                isRestTimerRunning = false
            }
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
                presentFinishSheet()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This workout has no saved sets yet.")
        }
        .onSubmit {
            switch focusedField {
            case .workoutComment:
                persistWorkoutMetadata()
            case .weight:
                focusedField = .reps
            case .reps:
                focusedField = .setComment
            case .setComment:
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

    private var resolvedStartedAt: Date {
        let calendar = Calendar.current
        let workoutDay = calendar.dateComponents([.year, .month, .day], from: workoutDate)
        let startTime = calendar.dateComponents([.hour, .minute, .second], from: workoutStartedAt)
        var components = DateComponents()
        components.year = workoutDay.year
        components.month = workoutDay.month
        components.day = workoutDay.day
        components.hour = startTime.hour
        components.minute = startTime.minute
        components.second = startTime.second
        return calendar.date(from: components) ?? workoutStartedAt
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        }

        return String(format: "%dm %02ds", minutes, seconds)
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let clampedSeconds = max(seconds, 0)
        let minutes = clampedSeconds / 60
        let remainingSeconds = clampedSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func presentFinishSheet() {
        let startedAt = resolvedStartedAt
        let now = Date()
        workoutFinishedAt = max(now, startedAt)
        showingFinishSheet = true
    }

    private func startRestTimer() {
        guard selectedExerciseDefaultRestSeconds > 0 else {
            return
        }

        restTimerTotalSeconds = selectedExerciseDefaultRestSeconds
        restTimerRemainingSeconds = selectedExerciseDefaultRestSeconds
        isRestTimerRunning = true
    }

    private func pauseRestTimer() {
        isRestTimerRunning = false
    }

    private func resumeRestTimer() {
        guard restTimerRemainingSeconds > 0 else {
            startRestTimer()
            return
        }

        isRestTimerRunning = true
    }

    private func clearRestTimer() {
        isRestTimerRunning = false
        restTimerRemainingSeconds = 0
        restTimerTotalSeconds = selectedExerciseDefaultRestSeconds
    }

    private func syncRestTimerForExerciseChange() {
        guard !isRestTimerRunning else {
            return
        }

        if restTimerRemainingSeconds == 0 {
            restTimerTotalSeconds = selectedExerciseDefaultRestSeconds
        }
    }

    private var restTimerSection: some View {
        Section("Rest Timer") {
            Group {
                if let selectedExercise {
                    LabeledContent("Exercise") {
                        Text(selectedExercise.name)
                    }
                }
            }

            LabeledContent("Default Rest") {
                Text(selectedExerciseDefaultRestSeconds > 0 ? formatSeconds(selectedExerciseDefaultRestSeconds) : "Off")
            }

            if shouldShowRestTimer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(formatSeconds(restTimerRemainingSeconds))
                            .font(.title2.monospacedDigit())
                        Spacer()
                        Text(restTimerStatusText)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: restTimerProgress)
                }

                if isRestTimerRunning {
                    Button("Pause Rest Timer") {
                        pauseRestTimer()
                    }

                    Button("Restart Rest Timer") {
                        startRestTimer()
                    }

                    Button("Skip Rest Timer") {
                        clearRestTimer()
                    }
                } else {
                    Button(restTimerRemainingSeconds > 0 ? "Resume Rest Timer" : "Start Rest Timer") {
                        restTimerRemainingSeconds > 0 ? resumeRestTimer() : startRestTimer()
                    }
                    .disabled(selectedExerciseDefaultRestSeconds == 0)

                    if selectedExerciseDefaultRestSeconds > 0 {
                        Button("Restart Rest Timer") {
                            startRestTimer()
                        }
                    }
                }
            }
        }
    }

    private var workoutSummarySection: some View {
        Section("Workout Summary") {
            Group {
                if groupedSets.isEmpty {
                    ContentUnavailableView(
                        "Workout is empty",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Add at least one set to see the workout summary.")
                    )
                } else {
                    ForEach(groupedSets, id: \.id) { group in
                        WorkoutExerciseSummaryView(group: group)
                    }
                    .onMove(perform: moveExerciseGroups)

                    ShareLink(
                        item: workoutShareText,
                        preview: SharePreview("Workout Summary", image: Image(systemName: "square.and.arrow.up"))
                    ) {
                        Label("Share Workout", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .id(SectionAnchor.summary)
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
        focusedField = nil

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
            _ = try workoutStore.addSet(
                to: workout,
                exercise: selectedExercise,
                weight: weight,
                reps: reps,
                comment: setCommentText,
                isCompleted: true
            )
            weightText = ""
            repsText = ""
            setCommentText = ""
            startRestTimer()
            focusedField = .weight
        } catch {
            alertMessage = "The set could not be saved."
        }
    }

    private func handleFinishTapped() {
        if allSets.isEmpty {
            showingFinishEmptyConfirmation = true
        } else {
            presentFinishSheet()
        }
    }

    private func finishWorkout() {
        do {
            let startedAt = resolvedStartedAt
            let finishedAt = max(workoutFinishedAt, startedAt)
            try workoutStore.updateWorkout(
                workout,
                date: startedAt,
                startedAt: startedAt,
                finishedAt: nil,
                comment: workoutComment
            )
            try workoutStore.finishWorkout(workout, finishedAt: finishedAt)
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

    private func moveCurrentExerciseSets(from offsets: IndexSet, to destination: Int) {
        guard let selectedExercise else { return }

        do {
            try workoutStore.moveSets(in: workout, exercise: selectedExercise, fromOffsets: offsets, toOffset: destination)
        } catch {
            alertMessage = "The set order could not be updated."
        }
    }

    private func moveExerciseGroups(from offsets: IndexSet, to destination: Int) {
        guard canReorderExerciseGroups else { return }

        var reorderedGroups = groupedSets
        reorderedGroups.move(fromOffsets: offsets, toOffset: destination)
        let orderedExerciseIDs = reorderedGroups.compactMap { $0.exercise?.persistentModelID }

        do {
            try workoutStore.reorderExerciseGroups(in: workout, orderedExerciseIDs: orderedExerciseIDs)
        } catch {
            alertMessage = "The exercise order could not be updated."
        }
    }

    private func persistWorkoutMetadata() {
        focusedField = nil
        let startedAt = resolvedStartedAt

        do {
            try workoutStore.updateWorkout(
                workout,
                date: startedAt,
                startedAt: startedAt,
                finishedAt: workout.finishedAt,
                comment: workoutComment
            )
            alertMessage = "Workout details saved."
        } catch {
            alertMessage = "The workout details could not be saved."
        }
    }

    private var workoutShareText: String {
        let header = "Workout on \(workout.date.formatted(date: .abbreviated, time: .shortened))"
        let commentLine = workout.comment.isEmpty ? nil : "Comment: \(workout.comment)"
        let lines = groupedSets.flatMap { group in
            [group.title] + group.sets.map {
                "Set \($0.setOrder): \($0.weight.formatted(.number.precision(.fractionLength(0...2)))) kg x \($0.reps)\($0.comment.isEmpty ? "" : " (\($0.comment))")"
            }
        }
        return ([header] + (commentLine.map { [$0] } ?? []) + lines).joined(separator: "\n")
    }

    private var addSetSection: some View {
        Section("Add Set") {
            TextField("Weight", text: $weightText)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .weight)
                .submitLabel(.next)

            TextField("Reps", text: $repsText)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .reps)
                .submitLabel(.done)

            TextField("Set comment", text: $setCommentText)
                .focused($focusedField, equals: .setComment)

            Button("Save Set") {
                saveSet()
            }
            .disabled(!canAddSet)
        }
    }

    private var currentExerciseSection: some View {
        Section(currentExerciseSectionTitle) {
            Group {
                if currentExerciseSets.isEmpty {
                    Text("Add the first set for the selected exercise.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(currentExerciseSets) { workoutSet in
                        SetRowView(set: workoutSet) {
                            editingSet = workoutSet
                        }
                    }
                    .onDelete(perform: deleteCurrentExerciseSets)
                    .onMove(perform: moveCurrentExerciseSets)
                }
            }
        }
    }
}

private extension WorkoutBuilderView {
    enum EntryField {
        case workoutComment
        case weight
        case reps
        case setComment
    }

    enum SectionAnchor: Hashable {
        case summary
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
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Set \(set.setOrder)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(set.weight.formatted(.number.precision(.fractionLength(0...2)))) kg")
                    Text("x")
                        .foregroundStyle(.secondary)
                    Text("\(set.reps)")
                }

                if !set.comment.isEmpty {
                    Text(set.comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

private struct FinishWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss

    let startedAt: Date
    @Binding var finishedAt: Date
    let durationText: String
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Timing") {
                    LabeledContent("Started") {
                        Text(startedAt.formatted(date: .abbreviated, time: .shortened))
                    }

                    DatePicker("Finish Time", selection: $finishedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])

                    LabeledContent("Duration") {
                        Text(durationText)
                    }
                }
            }
            .navigationTitle("Finish Workout")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") {
                        onFinish()
                    }
                }
            }
        }
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
                SetRowView(set: workoutSet, onEdit: {})
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

private struct SetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isKeyboardFocused: Bool

    let set: WorkoutSet

    @State private var weightText: String
    @State private var repsText: String
    @State private var comment: String
    @State private var errorMessage: String?

    init(set: WorkoutSet) {
        self.set = set
        _weightText = State(initialValue: set.weight.formatted(.number.precision(.fractionLength(0...2))))
        _repsText = State(initialValue: "\(set.reps)")
        _comment = State(initialValue: set.comment)
    }

    private var workoutStore: DefaultWorkoutStore {
        DefaultWorkoutStore(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($isKeyboardFocused)
                TextField("Reps", text: $repsText)
                    .keyboardType(.numberPad)
                    .focused($isKeyboardFocused)
                TextField("Comment", text: $comment, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($isKeyboardFocused)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Edit Set")
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
        guard let weight = Double(weightText.replacingOccurrences(of: ",", with: ".")),
              let reps = Int(repsText) else {
            errorMessage = "Enter a valid weight and rep count."
            return
        }

        do {
            try workoutStore.updateSet(set, weight: weight, reps: reps, comment: comment, isCompleted: true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
