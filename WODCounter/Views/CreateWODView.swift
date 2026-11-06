import SwiftUI
import SwiftData
import Foundation

struct CreateWODView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Movement.name) private var movements: [Movement]

    /// The workout being edited, if any. `nil` means create a new workout.
    private let editingWorkout: Workout?

    @State private var name = ""
    @State private var mode: ExecutionMode = .topTime
    @State private var forTimeMinutes = 20
    @State private var repeatTimes = 1
    @State private var restAfterBlock = 0
    @State private var drafts: [ExerciseDraft] = []
    @State private var newMovementName = ""
    @State private var errorMessage: String?

    static let distanceUnits = ["m", "km", "mi", "ft"]

    // MARK: - Draft Model

    init(editingWorkout: Workout? = nil) {
        self.editingWorkout = editingWorkout
        let draft = editingWorkout.map { Self.draft(from: $0) }
            ?? WorkoutDraft(name: "", mode: .topTime, forTimeMinutes: 20,
                            repeatTimes: 1, restAfterBlock: 0, exercises: [])
        _name = State(initialValue: draft.name)
        _mode = State(initialValue: draft.mode)
        _forTimeMinutes = State(initialValue: draft.forTimeMinutes)
        _repeatTimes = State(initialValue: draft.repeatTimes)
        _restAfterBlock = State(initialValue: draft.restAfterBlock)
        _drafts = State(initialValue: draft.exercises)
    }

    struct WorkoutDraft {
        var name: String
        var mode: ExecutionMode
        var forTimeMinutes: Int
        var repeatTimes: Int
        var restAfterBlock: Int
        var exercises: [ExerciseDraft]
    }

    struct ExerciseDraft: Identifiable {
        let id: UUID
        var movementName: String
        var reps: Int
        var weight: String
        var distance: String
        var distanceUnit: String
        /// The persisted exercise this draft came from, when editing. Creation
        /// drafts leave this `nil` and always insert new `Exercise` rows.
        var existingExercise: Exercise?

        init(id: UUID = UUID(),
             movementName: String,
             reps: Int = 0,
             weight: String = "",
             distance: String = "",
             distanceUnit: String = "m",
             existingExercise: Exercise? = nil) {
            self.id = id
            self.movementName = movementName
            self.reps = reps
            self.weight = weight
            self.distance = distance
            self.distanceUnit = distanceUnit
            self.existingExercise = existingExercise
        }
    }

    /// Loads an existing workout's editable fields in explicit `sortOrder`.
    static func draft(from workout: Workout) -> WorkoutDraft {
        let block = workout.orderedBlocks.first
        let exercises = (block?.orderedExercises ?? []).map { exercise in
            ExerciseDraft(
                movementName: exercise.movement?.name ?? "",
                reps: exercise.reps ?? 0,
                weight: exercise.weight ?? "",
                distance: exercise.distance ?? "",
                distanceUnit: exercise.distanceUnit ?? "m",
                existingExercise: exercise
            )
        }
        return WorkoutDraft(
            name: workout.name,
            mode: workout.mode,
            forTimeMinutes: workout.forTimeMinutes ?? 20,
            repeatTimes: max(1, block?.repeatTimes ?? 1),
            restAfterBlock: block?.restAfterBlock ?? 0,
            exercises: exercises
        )
    }

    enum ValidationError: LocalizedError, Equatable {
        case emptyName
        case noExercises
        case invalidExercise(String)
        case missingTimeCap
        case builtinNotEditable

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Give your workout a name."
            case .noExercises:
                return "Add at least one exercise."
            case .invalidExercise(let movement):
                return "\(movement) needs reps or a distance."
            case .missingTimeCap:
                return "For Time workouts need a time cap."
            case .builtinNotEditable:
                return "Built-in workouts cannot be edited."
            }
        }
    }

    // MARK: - Display Label Rendering (pre-rendered at creation time)

    static func displayLabel(for draft: ExerciseDraft) -> String {
        displayLabel(
            reps: draft.reps > 0 ? draft.reps : nil,
            weight: draft.weight.trimmed.isEmpty ? nil : draft.weight.trimmed,
            distance: draft.distance,
            distanceUnit: draft.distanceUnit,
            movementName: draft.movementName
        )
    }

    static func displayLabel(reps: Int?,
                             weight: String?,
                             distance: String?,
                             distanceUnit: String?,
                             movementName: String) -> String {
        if let reps, reps > 0 {
            let base = "\(reps) \(pluralized(movementName, for: reps))"
            if let weight, !weight.trimmed.isEmpty {
                return "\(base) (\(weight.trimmed))"
            }
            return base
        }
        if let composed = composeDistance(distance ?? "", unit: distanceUnit ?? "") {
            return "\(composed) \(movementName)"
        }
        return movementName
    }

    static func composeDistance(_ text: String, unit: String) -> String? {
        let value = text.trimmed
        guard !value.isEmpty else { return nil }
        let u = unit.trimmed
        guard !u.isEmpty else { return value }
        if value == u || value.hasSuffix(" \(u)") { return value }
        if let last = value.last, last.isLetter { return value }
        return "\(value) \(u)"
    }

    static func pluralized(_ movementName: String, for count: Int) -> String {
        if count == 1 {
            if movementName.hasSuffix("s") && !movementName.hasSuffix("ss") {
                return String(movementName.dropLast())
            }
            return movementName
        }
        if movementName.hasSuffix("s") || movementName.hasSuffix("S") { return movementName }
        return movementName + "s"
    }

    // MARK: - Validation

    static func validate(name: String,
                         drafts: [ExerciseDraft],
                         mode: ExecutionMode,
                         forTimeMinutes: Int) throws {
        guard !name.trimmed.isEmpty else { throw ValidationError.emptyName }
        guard !drafts.isEmpty else { throw ValidationError.noExercises }
        for draft in drafts {
            let hasReps = draft.reps > 0
            let hasDistance = !draft.distance.trimmed.isEmpty
            guard hasReps || hasDistance else {
                throw ValidationError.invalidExercise(draft.movementName)
            }
        }
        if mode == .forTime {
            guard forTimeMinutes > 0 else { throw ValidationError.missingTimeCap }
        }
    }

    // MARK: - Workout Building

    static func makeWorkout(name: String,
                            mode: ExecutionMode,
                            forTimeMinutes: Int,
                            repeatTimes: Int,
                            restAfterBlock: Int,
                            drafts: [ExerciseDraft],
                            in context: ModelContext) -> Workout {
        let block = RoundBlock(
            repeatTimes: mode == .forTime ? 0 : max(1, repeatTimes),
            restAfterBlock: restAfterBlock > 0 ? restAfterBlock : nil,
            sortOrder: 0
        )
        var exercises: [Exercise] = []
        exercises.reserveCapacity(drafts.count)
        for (index, draft) in drafts.enumerated() {
            let exercise = Exercise()
            context.insert(exercise)
            configure(exercise, from: draft, sortOrder: index, in: context)
            exercises.append(exercise)
        }
        block.exercises = exercises

        let workout = Workout(
            name: name.trimmed,
            category: "Custom",
            mode: mode,
            isBuiltin: false,
            forTimeMinutes: mode == .forTime ? forTimeMinutes : nil
        )
        workout.blocks = [block]
        return workout
    }

    /// Applies edits to an existing custom workout in place.
    ///
    /// Validation happens before any mutation so a rejected edit leaves both the
    /// in-memory model and the store untouched. Existing `Exercise` rows are
    /// reused, removed rows are deleted, and added rows are inserted.
    static func updateWorkout(_ workout: Workout,
                              name: String,
                              mode: ExecutionMode,
                              forTimeMinutes: Int,
                              repeatTimes: Int,
                              restAfterBlock: Int,
                              drafts: [ExerciseDraft],
                              in context: ModelContext) throws {
        guard !workout.isBuiltin else { throw ValidationError.builtinNotEditable }
        try validate(name: name, drafts: drafts, mode: mode, forTimeMinutes: forTimeMinutes)

        let block: RoundBlock
        if let existing = workout.orderedBlocks.first {
            block = existing
        } else {
            let newBlock = RoundBlock(repeatTimes: 1, sortOrder: 0)
            context.insert(newBlock)
            workout.blocks = [newBlock]
            block = newBlock
        }

        let previousExercises = block.orderedExercises
        var updatedExercises: [Exercise] = []
        updatedExercises.reserveCapacity(drafts.count)

        for (index, draft) in drafts.enumerated() {
            let exercise: Exercise
            if let existing = draft.existingExercise, existing.roundBlock === block {
                exercise = existing
            } else {
                exercise = Exercise()
                context.insert(exercise)
            }
            configure(exercise, from: draft, sortOrder: index, in: context)
            updatedExercises.append(exercise)
        }

        block.exercises = updatedExercises
        for exercise in previousExercises
        where !updatedExercises.contains(where: { $0 === exercise }) {
            context.delete(exercise)
        }

        block.repeatTimes = mode == .forTime ? 0 : max(1, repeatTimes)
        block.restAfterBlock = restAfterBlock > 0 ? restAfterBlock : nil
        block.sortOrder = 0

        workout.name = name.trimmed
        workout.mode = mode
        workout.forTimeMinutes = mode == .forTime ? forTimeMinutes : nil
        workout.category = "Custom"
        workout.updatedAt = Date()
    }

    private static func configure(_ exercise: Exercise,
                                  from draft: ExerciseDraft,
                                  sortOrder: Int,
                                  in context: ModelContext) {
        exercise.movement = movement(named: draft.movementName, in: context)
        exercise.reps = draft.reps > 0 ? draft.reps : nil
        exercise.weight = draft.weight.trimmed.isEmpty ? nil : draft.weight.trimmed
        let distance = composeDistance(draft.distance, unit: draft.distanceUnit)
        exercise.distance = distance
        exercise.distanceUnit = (distance != nil && !draft.distanceUnit.trimmed.isEmpty)
            ? draft.distanceUnit.trimmed : nil
        exercise.displayLabel = displayLabel(for: draft)
        exercise.sortOrder = sortOrder
    }

    private static func movement(named name: String, in context: ModelContext) -> Movement {
        let trimmed = name.trimmed
        let descriptor = FetchDescriptor<Movement>(predicate: #Predicate { $0.name == trimmed })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let movement = Movement(name: trimmed)
        context.insert(movement)
        return movement
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section("Name") {
                TextField("Workout Name", text: $name)
            }

            Section("Mode") {
                Picker("Mode", selection: $mode) {
                    ForEach(ExecutionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .forTime {
                    Stepper("Time Cap: \(forTimeMinutes) min", value: $forTimeMinutes, in: 1...180)
                }
            }

            Section {
                ForEach(catalogNames, id: \.self) { movementName in
                    Toggle(movementName, isOn: selectionBinding(for: movementName))
                }
                HStack {
                    TextField("New movement name", text: $newMovementName)
                        .textInputAutocapitalization(.words)
                    Button {
                        addNewMovement()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newMovementName.trimmed.isEmpty)
                }
            } header: {
                Text("Movements")
            } footer: {
                Text("New movements are added to the catalog when you save.")
            }

            exerciseConfiguration

            Section {
                if mode == .forTime {
                    LabeledContent("Repeat", value: "Continuous (AMRAP)")
                } else {
                    Stepper(value: $repeatTimes, in: 1...99) {
                        Text(repeatTimes == 1 ? "1 Round" : "\(repeatTimes) Rounds")
                    }
                }
                TextField("Rest after block (s)", value: $restAfterBlock, format: .number)
            } header: {
                Text("Block Settings")
            } footer: {
                Text("Rest applies after each completed round of this block, not after the final round of the workout.")
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        Label(editingWorkout == nil ? "Save Workout" : "Save Changes",
                              systemImage: "checkmark")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(editingWorkout == nil ? "Create WOD" : "Edit WOD")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .alert("Cannot Save", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var exerciseConfiguration: some View {
        if !drafts.isEmpty {
            ForEach(drafts) { draft in
                let binding = draftBinding(draft.id)
                Section {
                    TextField("Reps", value: binding.reps, format: .number)
                    TextField("Weight", text: binding.weight, prompt: Text("e.g. 95 lb"))
                    TextField("Distance", text: binding.distance, prompt: Text("e.g. 400"))
                    Picker("Distance Unit", selection: binding.distanceUnit) {
                        ForEach(Self.distanceUnits, id: \.self) { unit in
                            Text(unit).tag(unit)
                        }
                    }
                } header: {
                    Text(draft.movementName)
                } footer: {
                    Text(footerText(for: draft))
                }
            }
        }
    }

    // MARK: - State Helpers

    private var catalogNames: [String] {
        var names = movements.map(\.name)
        for draft in drafts where !names.contains(draft.movementName) {
            names.append(draft.movementName)
        }
        return names
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func selectionBinding(for movementName: String) -> Binding<Bool> {
        Binding(
            get: { drafts.contains { $0.movementName == movementName } },
            set: { selected in
                if selected {
                    if !drafts.contains(where: { $0.movementName == movementName }) {
                        drafts.append(ExerciseDraft(movementName: movementName))
                    }
                } else {
                    drafts.removeAll { $0.movementName == movementName }
                }
            }
        )
    }

    private func draftBinding(_ id: UUID) -> Binding<ExerciseDraft> {
        Binding(
            get: { drafts.first(where: { $0.id == id }) ?? ExerciseDraft(movementName: "") },
            set: { updated in
                guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
                drafts[index] = updated
            }
        )
    }

    private func footerText(for draft: ExerciseDraft) -> String {
        let label = Self.displayLabel(for: draft)
        guard label != draft.movementName else {
            return "Add reps or distance to preview the display label."
        }
        return "Displays as: \(label)"
    }

    private func addNewMovement() {
        let trimmed = newMovementName.trimmed
        guard !trimmed.isEmpty else { return }
        if !drafts.contains(where: { $0.movementName == trimmed }) {
            drafts.append(ExerciseDraft(movementName: trimmed))
        }
        newMovementName = ""
    }

    private func save() {
        do {
            try Self.validate(
                name: name,
                drafts: drafts,
                mode: mode,
                forTimeMinutes: forTimeMinutes
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            if let editingWorkout {
                try Self.updateWorkout(
                    editingWorkout,
                    name: name,
                    mode: mode,
                    forTimeMinutes: forTimeMinutes,
                    repeatTimes: repeatTimes,
                    restAfterBlock: restAfterBlock,
                    drafts: drafts,
                    in: modelContext
                )
            } else {
                let workout = Self.makeWorkout(
                    name: name,
                    mode: mode,
                    forTimeMinutes: forTimeMinutes,
                    repeatTimes: repeatTimes,
                    restAfterBlock: restAfterBlock,
                    drafts: drafts,
                    in: modelContext
                )
                modelContext.insert(workout)
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
