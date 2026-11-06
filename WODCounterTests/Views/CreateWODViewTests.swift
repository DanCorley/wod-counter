import Testing
import SwiftData
import Foundation
@testable import WODCounter

@MainActor
struct CreateWODViewTests {
    typealias Draft = CreateWODView.ExerciseDraft
    typealias ValidationError = CreateWODView.ValidationError

    // MARK: - Helpers

    private func makeContext() -> ModelContext {
        ModelContext(Container.inMemory())
    }

    private func exercisesByMovement(_ block: RoundBlock) -> [String: Exercise] {
        Dictionary(uniqueKeysWithValues: block.orderedExercises.compactMap { exercise in
            exercise.movement.map { ($0.name, exercise) }
        })
    }

    // MARK: - Pre-rendered displayLabel Generation

    @Test func displayLabelRepsWithWeight() {
        let label = CreateWODView.displayLabel(
            reps: 21, weight: "95 lb", distance: nil, distanceUnit: nil,
            movementName: "Thrusters"
        )
        #expect(label == "21 Thrusters (95 lb)")
    }

    @Test func displayLabelRepsWithoutWeight() {
        let label = CreateWODView.displayLabel(
            reps: 100, weight: nil, distance: nil, distanceUnit: nil,
            movementName: "Pull-up"
        )
        #expect(label == "100 Pull-ups")
    }

    @Test func displayLabelPluralizesMovementName() {
        let label = CreateWODView.displayLabel(
            reps: 12, weight: "225 lb", distance: nil, distanceUnit: nil,
            movementName: "Deadlift"
        )
        #expect(label == "12 Deadlifts (225 lb)")
    }

    @Test func displayLabelSingularForOneRep() {
        let label = CreateWODView.displayLabel(
            reps: 1, weight: nil, distance: nil, distanceUnit: nil,
            movementName: "Thrusters"
        )
        #expect(label == "1 Thruster")
    }

    @Test func displayLabelDistanceValuePlusUnit() {
        let label = CreateWODView.displayLabel(
            reps: nil, weight: nil, distance: "400", distanceUnit: "m",
            movementName: "Run"
        )
        #expect(label == "400 m Run")
    }

    @Test func displayLabelDistanceAlreadyContainsUnit() {
        let label = CreateWODView.displayLabel(
            reps: nil, weight: nil, distance: "400 m", distanceUnit: "m",
            movementName: "Run"
        )
        #expect(label == "400 m Run")
    }

    @Test func displayLabelFallsBackToMovementName() {
        let label = CreateWODView.displayLabel(
            reps: nil, weight: nil, distance: "", distanceUnit: "m",
            movementName: "Pull-up"
        )
        #expect(label == "Pull-up")
    }

    @Test func composeDistanceAppendsUnitToBareValue() {
        #expect(CreateWODView.composeDistance("400", unit: "m") == "400 m")
        #expect(CreateWODView.composeDistance("5", unit: "km") == "5 km")
    }

    @Test func composeDistanceKeepsValueThatAlreadyHasUnit() {
        #expect(CreateWODView.composeDistance("400 m", unit: "m") == "400 m")
        #expect(CreateWODView.composeDistance("400", unit: "") == "400")
        #expect(CreateWODView.composeDistance("", unit: "m") == nil)
    }

    @Test func displayLabelFromDraft() {
        let draft = Draft(movementName: "Thrusters", reps: 21, weight: "95 lb")
        #expect(CreateWODView.displayLabel(for: draft) == "21 Thrusters (95 lb)")

        let runDraft = Draft(movementName: "Run", distance: "400", distanceUnit: "m")
        #expect(CreateWODView.displayLabel(for: runDraft) == "400 m Run")
    }

    // MARK: - Workout Creation and Insertion

    @Test func makeWorkoutBuildsAndInsertsTopTimeWorkout() throws {
        let context = makeContext()
        let drafts = [
            Draft(movementName: "Thrusters", reps: 21, weight: "95 lb"),
            Draft(movementName: "Run", distance: "400", distanceUnit: "m"),
            Draft(movementName: "Pull-up", reps: 100),
        ]

        let workout = CreateWODView.makeWorkout(
            name: "Sprint Chipper",
            mode: .topTime,
            forTimeMinutes: 0,
            repeatTimes: 3,
            restAfterBlock: 60,
            drafts: drafts,
            in: context
        )
        context.insert(workout)
        try context.save()

        let fetched = try context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.name == "Sprint Chipper" })
        )
        #expect(fetched.count == 1)

        let saved = try #require(fetched.first)
        #expect(saved.category == "Custom")
        #expect(saved.isBuiltin == false)
        #expect(saved.mode == .topTime)
        #expect(saved.forTimeMinutes == nil)
        #expect(saved.orderedBlocks.count == 1)

        let block = try #require(saved.orderedBlocks.first)
        #expect(block.repeatTimes == 3)
        #expect(block.restAfterBlock == 60)
        #expect(block.orderedExercises.count == 3)

        // Explicit sortOrder preserves draft order regardless of relationship array order.
        #expect(block.orderedExercises.map { $0.displayLabel }
                == ["21 Thrusters (95 lb)", "400 m Run", "100 Pull-ups"])
        #expect(block.orderedExercises.map(\.sortOrder) == [0, 1, 2])

        let byName = exercisesByMovement(block)

        let thrusters = try #require(byName["Thrusters"])
        #expect(thrusters.displayLabel == "21 Thrusters (95 lb)")
        #expect(thrusters.reps == 21)
        #expect(thrusters.weight == "95 lb")
        #expect(thrusters.restSeconds == nil)

        let run = try #require(byName["Run"])
        #expect(run.displayLabel == "400 m Run")
        #expect(run.reps == nil)
        #expect(run.distance == "400 m")
        #expect(run.distanceUnit == "m")

        let pullUps = try #require(byName["Pull-up"])
        #expect(pullUps.displayLabel == "100 Pull-ups")
        #expect(pullUps.weight == nil)

        // Relationships set via property assignment resolve as inverses.
        for exercise in block.orderedExercises {
            #expect(exercise.roundBlock == block)
        }
        #expect(block.workout == saved)
    }

    @Test func customWorkoutPreservesDraftOrderAfterReload() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let drafts = [
            Draft(movementName: "Thrusters", reps: 21, weight: "95 lb"),
            Draft(movementName: "Pull-up", reps: 21),
            Draft(movementName: "Run", distance: "400", distanceUnit: "m"),
        ]

        let workout = CreateWODView.makeWorkout(
            name: "Ordered Custom",
            mode: .topTime,
            forTimeMinutes: 0,
            repeatTimes: 1,
            restAfterBlock: 0,
            drafts: drafts,
            in: context
        )
        context.insert(workout)
        try context.save()

        let reloadContext = ModelContext(container)
        let fetched = try reloadContext.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.name == "Ordered Custom" })
        )
        let reloaded = try #require(fetched.first)
        let block = try #require(reloaded.orderedBlocks.first)

        #expect(block.orderedExercises.map { $0.displayLabel }
                == ["21 Thrusters (95 lb)", "21 Pull-ups", "400 m Run"])
        #expect(block.orderedExercises.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func makeWorkoutBuildsForTimeWorkoutWithTimeCap() throws {
        let context = makeContext()
        let drafts = [Draft(movementName: "Air Squat", reps: 15)]

        let workout = CreateWODView.makeWorkout(
            name: "AMRAP 12",
            mode: .forTime,
            forTimeMinutes: 12,
            repeatTimes: 5, // ignored for for-time; AMRAP loop uses 0
            restAfterBlock: 0,
            drafts: drafts,
            in: context
        )
        context.insert(workout)
        try context.save()

        #expect(workout.mode == .forTime)
        #expect(workout.forTimeMinutes == 12)
        #expect(workout.category == "Custom")
        #expect(workout.isBuiltin == false)

        let block = try #require(workout.orderedBlocks.first)
        #expect(block.repeatTimes == 0)
        #expect(block.restAfterBlock == nil)
        #expect(block.orderedExercises.first?.displayLabel == "15 Air Squats")
    }

    @Test func customWorkoutWithBlockRestRestsBetweenRounds() throws {
        let context = makeContext()
        let drafts = [Draft(movementName: "Burpee", reps: 10)]

        let workout = CreateWODView.makeWorkout(
            name: "Rest Custom",
            mode: .topTime,
            forTimeMinutes: 0,
            repeatTimes: 2,
            restAfterBlock: 45,
            drafts: drafts,
            in: context
        )
        context.insert(workout)
        try context.save()

        var sim = WODSimulator(workout: workout)
        sim.start()

        let firstRound = try #require(sim.liveTasks.first { !$0.isComplete })
        #expect(sim.completeReps(taskID: firstRound.id, count: firstRound.remaining) == .blockCompleted)
        #expect(sim.phase == .resting)
        #expect(sim.restDeadline == 45)

        _ = sim.endRest()
        let finalRound = try #require(sim.liveTasks.first { !$0.isComplete })
        #expect(sim.completeReps(taskID: finalRound.id, count: finalRound.remaining) == .finished(.goalReached))
        #expect(sim.phase == .finished)
        #expect(sim.restDeadline == nil)
    }

    @Test func customWorkoutAppearsUnderCustomCategoryInQuery() throws {
        let context = makeContext()
        let drafts = [Draft(movementName: "Deadlift", reps: 12, weight: "225 lb")]

        let workout = CreateWODView.makeWorkout(
            name: "My WOD",
            mode: .topTime,
            forTimeMinutes: 0,
            repeatTimes: 1,
            restAfterBlock: 0,
            drafts: drafts,
            in: context
        )
        context.insert(workout)
        try context.save()

        // HomeView fetches all workouts and filters with isCustom.
        let all = try context.fetch(FetchDescriptor<Workout>())
        let custom = all.filter { $0.isCustom }
        #expect(custom.map(\.name) == ["My WOD"])
        #expect(custom[0].category == "Custom")
        #expect(custom[0].isCustom)

        let byCategory = try context.fetchCount(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.category == "Custom" })
        )
        #expect(byCategory == 1)
    }

    @Test func newWorkoutReusesSeededMovementCatalogEntry() throws {
        let context = makeContext()
        _ = BenchmarkSeed.cindy(in: context)

        let drafts = [Draft(movementName: "Pull-up", reps: 5)]
        let workout = CreateWODView.makeWorkout(
            name: "Pull-up Party",
            mode: .topTime,
            forTimeMinutes: 0,
            repeatTimes: 1,
            restAfterBlock: 0,
            drafts: drafts,
            in: context
        )
        context.insert(workout)
        try context.save()

        let pullUps = try context.fetch(
            FetchDescriptor<Movement>(predicate: #Predicate { $0.name == "Pull-up" })
        )
        #expect(pullUps.count == 1)
        #expect(workout.orderedBlocks.first?.orderedExercises.first?.movement == pullUps[0])
    }

    // MARK: - Validation

    @Test func emptyNameIsRejected() {
        #expect(throws: ValidationError.emptyName) {
            try CreateWODView.validate(
                name: "   ",
                drafts: [Draft(movementName: "Run", distance: "400")],
                mode: .topTime,
                forTimeMinutes: 0
            )
        }
    }

    @Test func noExercisesIsRejected() {
        #expect(throws: ValidationError.noExercises) {
            try CreateWODView.validate(
                name: "My WOD",
                drafts: [],
                mode: .topTime,
                forTimeMinutes: 0
            )
        }
    }

    @Test func exerciseWithoutRepsOrDistanceIsRejected() {
        #expect(throws: ValidationError.invalidExercise("Pull-up")) {
            try CreateWODView.validate(
                name: "My WOD",
                drafts: [Draft(movementName: "Pull-up")],
                mode: .topTime,
                forTimeMinutes: 0
            )
        }
    }

    @Test func forTimeRequiresTimeCap() {
        #expect(throws: ValidationError.missingTimeCap) {
            try CreateWODView.validate(
                name: "My WOD",
                drafts: [Draft(movementName: "Air Squat", reps: 15)],
                mode: .forTime,
                forTimeMinutes: 0
            )
        }
    }

    @Test func validInputsPassValidation() throws {
        try CreateWODView.validate(
            name: "Fran-ish",
            drafts: [
                Draft(movementName: "Thrusters", reps: 21, weight: "95 lb"),
                Draft(movementName: "Run", distance: "400", distanceUnit: "m"),
            ],
            mode: .forTime,
            forTimeMinutes: 20
        )

        try CreateWODView.validate(
            name: "Fran-ish",
            drafts: [Draft(movementName: "Pull-up", reps: 100)],
            mode: .topTime,
            forTimeMinutes: 0
        )
    }

    // MARK: - Editing Existing Workouts

    @discardableResult
    private func seedCustomWorkout(name: String = "Editable Workout",
                                   mode: ExecutionMode = .topTime,
                                   forTimeMinutes: Int = 0,
                                   repeatTimes: Int = 2,
                                   restAfterBlock: Int = 30,
                                   drafts: [Draft],
                                   in context: ModelContext) throws -> Workout {
        let workout = CreateWODView.makeWorkout(
            name: name,
            mode: mode,
            forTimeMinutes: forTimeMinutes,
            repeatTimes: repeatTimes,
            restAfterBlock: restAfterBlock,
            drafts: drafts,
            in: context
        )
        context.insert(workout)
        try context.save()
        return workout
    }

    @Test func draftLoadsExistingWorkoutFieldsInOrder() throws {
        let context = makeContext()
        let workout = try seedCustomWorkout(
            name: "Loaded Custom",
            mode: .topTime,
            repeatTimes: 3,
            restAfterBlock: 45,
            drafts: [
                Draft(movementName: "Thrusters", reps: 21, weight: "95 lb"),
                Draft(movementName: "Run", distance: "400", distanceUnit: "m"),
            ],
            in: context
        )

        let draft = CreateWODView.draft(from: workout)

        #expect(draft.name == "Loaded Custom")
        #expect(draft.mode == .topTime)
        #expect(draft.repeatTimes == 3)
        #expect(draft.restAfterBlock == 45)
        #expect(draft.exercises.map(\.movementName) == ["Thrusters", "Run"])
        #expect(draft.exercises.map(\.reps) == [21, 0])
        #expect(draft.exercises.map(\.weight) == ["95 lb", ""])
        #expect(draft.exercises.map(\.distance) == ["", "400 m"])
        #expect(draft.exercises.map(\.distanceUnit) == ["m", "m"])

        let block = try #require(workout.orderedBlocks.first)
        #expect(draft.exercises[0].existingExercise === block.orderedExercises[0])
        #expect(draft.exercises[1].existingExercise === block.orderedExercises[1])
    }

    @Test func draftLoadsForTimeAndTimeCap() throws {
        let context = makeContext()
        let workout = try seedCustomWorkout(
            name: "AMRAP Loaded",
            mode: .forTime,
            forTimeMinutes: 12,
            repeatTimes: 5,
            restAfterBlock: 0,
            drafts: [Draft(movementName: "Air Squat", reps: 15)],
            in: context
        )

        let draft = CreateWODView.draft(from: workout)

        #expect(draft.mode == .forTime)
        #expect(draft.forTimeMinutes == 12)
        #expect(draft.repeatTimes == 1) // AMRAP blocks store repeatTimes == 0
        #expect(draft.restAfterBlock == 0)
    }

    @Test func editingUpdatesWorkoutInPlace() throws {
        let context = makeContext()
        let workout = try seedCustomWorkout(
            name: "Original Name",
            repeatTimes: 2,
            restAfterBlock: 30,
            drafts: [
                Draft(movementName: "Thrusters", reps: 21, weight: "95 lb"),
                Draft(movementName: "Run", distance: "400", distanceUnit: "m"),
            ],
            in: context
        )
        let originalCreatedAt = workout.createdAt
        workout.updatedAt = Date(timeIntervalSinceNow: -300)
        try context.save()

        var draft = CreateWODView.draft(from: workout)
        draft.name = "Edited Name"
        draft.restAfterBlock = 60
        draft.exercises[0].reps = 15
        draft.exercises[0].weight = "115 lb"
        draft.exercises[1].distance = "800"

        try CreateWODView.updateWorkout(
            workout,
            name: draft.name,
            mode: draft.mode,
            forTimeMinutes: draft.forTimeMinutes,
            repeatTimes: draft.repeatTimes,
            restAfterBlock: draft.restAfterBlock,
            drafts: draft.exercises,
            in: context
        )
        try context.save()

        let all = try context.fetch(FetchDescriptor<Workout>())
        #expect(all.count == 1)
        let saved = try #require(all.first)
        #expect(saved === workout)
        #expect(saved.name == "Edited Name")
        #expect(saved.createdAt == originalCreatedAt)
        #expect(saved.updatedAt > Date(timeIntervalSinceNow: -200))
        #expect(saved.category == "Custom")
        #expect(saved.isBuiltin == false)

        let block = try #require(saved.orderedBlocks.first)
        #expect(block.restAfterBlock == 60)
        #expect(block.orderedExercises.map(\.sortOrder) == [0, 1])

        let byName = exercisesByMovement(block)
        let thrusters = try #require(byName["Thrusters"])
        #expect(thrusters.reps == 15)
        #expect(thrusters.weight == "115 lb")
        #expect(thrusters.displayLabel == "15 Thrusters (115 lb)")

        let run = try #require(byName["Run"])
        #expect(run.distance == "800 m")
        #expect(run.distanceUnit == "m")
        #expect(run.displayLabel == "800 m Run")
    }

    @Test func editingRemovesAndAddsExercisesWithSequentialOrder() throws {
        let context = makeContext()
        let workout = try seedCustomWorkout(
            drafts: [
                Draft(movementName: "Thrusters", reps: 21, weight: "95 lb"),
                Draft(movementName: "Run", distance: "400", distanceUnit: "m"),
                Draft(movementName: "Pull-up", reps: 21),
            ],
            in: context
        )

        var draft = CreateWODView.draft(from: workout)
        draft.exercises.removeAll { $0.movementName == "Thrusters" }
        draft.exercises.append(Draft(movementName: "Burpee", reps: 10))

        try CreateWODView.updateWorkout(
            workout,
            name: draft.name,
            mode: draft.mode,
            forTimeMinutes: draft.forTimeMinutes,
            repeatTimes: draft.repeatTimes,
            restAfterBlock: draft.restAfterBlock,
            drafts: draft.exercises,
            in: context
        )
        try context.save()

        let blocks = workout.orderedBlocks
        #expect(blocks.count == 1)
        let block = try #require(blocks.first)
        #expect(block.orderedExercises.map { $0.movement?.name } == ["Run", "Pull-up", "Burpee"])
        #expect(block.orderedExercises.map(\.sortOrder) == [0, 1, 2])

        let remaining = try context.fetch(FetchDescriptor<Exercise>())
        #expect(remaining.count == 3)
        #expect(!remaining.contains { $0.movement?.name == "Thrusters" })
        #expect(remaining.contains { $0.movement?.name == "Burpee" && $0.reps == 10 })
    }

    @Test func editingBuiltinWorkoutIsRejected() throws {
        let context = makeContext()
        let cindy = BenchmarkSeed.cindy(in: context)
        context.insert(cindy)
        try context.save()

        let originalName = cindy.name
        let originalExerciseCount = cindy.orderedBlocks.first?.orderedExercises.count
        let draft = CreateWODView.draft(from: cindy)

        #expect(throws: ValidationError.builtinNotEditable) {
            try CreateWODView.updateWorkout(
                cindy,
                name: "Hacked Cindy",
                mode: draft.mode,
                forTimeMinutes: draft.forTimeMinutes,
                repeatTimes: draft.repeatTimes,
                restAfterBlock: draft.restAfterBlock,
                drafts: draft.exercises,
                in: context
            )
        }

        #expect(cindy.name == originalName)
        #expect(cindy.isBuiltin)
        #expect(cindy.orderedBlocks.first?.orderedExercises.count == originalExerciseCount)
    }

    @Test func invalidEditLeavesStoredWorkoutUnchanged() throws {
        let context = makeContext()
        let workout = try seedCustomWorkout(
            name: "Stable Workout",
            drafts: [
                Draft(movementName: "Thrusters", reps: 21, weight: "95 lb"),
                Draft(movementName: "Run", distance: "400", distanceUnit: "m"),
            ],
            in: context
        )

        let originalName = workout.name
        let originalRest = workout.orderedBlocks.first?.restAfterBlock
        let originalLabels = workout.orderedBlocks.first?.orderedExercises.map(\.displayLabel)

        var draft = CreateWODView.draft(from: workout)
        draft.name = "   "
        draft.restAfterBlock = 99
        draft.exercises.removeAll()

        #expect(throws: ValidationError.emptyName) {
            try CreateWODView.updateWorkout(
                workout,
                name: draft.name,
                mode: draft.mode,
                forTimeMinutes: draft.forTimeMinutes,
                repeatTimes: draft.repeatTimes,
                restAfterBlock: draft.restAfterBlock,
                drafts: draft.exercises,
                in: context
            )
        }

        #expect(workout.name == originalName)
        #expect(workout.orderedBlocks.first?.restAfterBlock == originalRest)
        #expect(workout.orderedBlocks.first?.orderedExercises.map(\.displayLabel) == originalLabels)
    }

    @Test func editedSchemeIsReadBySimulator() throws {
        let context = makeContext()
        let workout = try seedCustomWorkout(
            repeatTimes: 2,
            restAfterBlock: 0,
            drafts: [Draft(movementName: "Air Squat", reps: 10)],
            in: context
        )

        var draft = CreateWODView.draft(from: workout)
        draft.exercises[0].movementName = "Burpee"
        draft.exercises[0].reps = 25
        draft.restAfterBlock = 20

        try CreateWODView.updateWorkout(
            workout,
            name: draft.name,
            mode: draft.mode,
            forTimeMinutes: draft.forTimeMinutes,
            repeatTimes: draft.repeatTimes,
            restAfterBlock: draft.restAfterBlock,
            drafts: draft.exercises,
            in: context
        )
        try context.save()

        var simulator = WODSimulator(workout: workout)
        simulator.start()

        #expect(simulator.liveTasks.count == 2)
        #expect(simulator.liveTasks.allSatisfy {
            $0.movementName == "Burpee" && $0.quota == 25 && $0.displayLabel == "25 Burpees"
        })

        let firstRound = try #require(simulator.liveTasks.first { !$0.isComplete })
        #expect(simulator.completeReps(taskID: firstRound.id, count: firstRound.remaining) == .blockCompleted)
        #expect(simulator.phase == .resting)
        #expect(simulator.restDeadline == 20)
    }
}
