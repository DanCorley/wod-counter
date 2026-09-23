import SwiftUI
import SwiftData
import Foundation

struct CreateWODView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Movement.name) private var movements: [Movement]

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

    struct ExerciseDraft: Identifiable {
        let id: UUID
        var movementName: String
        var reps: Int
        var weight: String
        var distance: String
        var distanceUnit: String
        var restSeconds: Int

        init(id: UUID = UUID(),
             movementName: String,
             reps: Int = 0,
             weight: String = "",
             distance: String = "",
             distanceUnit: String = "m",
             restSeconds: Int = 0) {
            self.id = id
            self.movementName = movementName
            self.reps = reps
            self.weight = weight
            self.distance = distance
            self.distanceUnit = distanceUnit
            self.restSeconds = restSeconds
        }
    }

    enum ValidationError: LocalizedError, Equatable {
        case emptyName
        case noExercises
        case invalidExercise(String)
        case missingTimeCap

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
            restAfterBlock: restAfterBlock > 0 ? restAfterBlock : nil
        )
        var exercises: [Exercise] = []
        exercises.reserveCapacity(drafts.count)
        for draft in drafts {
            let movement = movement(named: draft.movementName, in: context)
            let reps = draft.reps > 0 ? draft.reps : nil
            let weight = draft.weight.trimmed.isEmpty ? nil : draft.weight.trimmed
            let distance = composeDistance(draft.distance, unit: draft.distanceUnit)
            let unit = (distance != nil && !draft.distanceUnit.trimmed.isEmpty)
                ? draft.distanceUnit.trimmed : nil
            let rest = draft.restSeconds > 0 ? draft.restSeconds : nil
            let exercise = Exercise(
                movement: movement,
                reps: reps,
                weight: weight,
                distance: distance,
                distanceUnit: unit,
                restSeconds: rest,
                displayLabel: displayLabel(for: draft)
            )
            context.insert(exercise)
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

            Section("Block Settings") {
                if mode == .forTime {
                    LabeledContent("Repeat", value: "Continuous (AMRAP)")
                } else {
                    Stepper(value: $repeatTimes, in: 1...99) {
                        Text(repeatTimes == 1 ? "1 Round" : "\(repeatTimes) Rounds")
                    }
                }
                TextField("Rest after block (s)", value: $restAfterBlock, format: .number)
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        Label("Save Workout", systemImage: "checkmark")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Create WOD")
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
                    TextField("Rest After (s)", value: binding.restSeconds, format: .number)
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
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
