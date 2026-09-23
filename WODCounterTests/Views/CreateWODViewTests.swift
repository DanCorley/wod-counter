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
        Dictionary(uniqueKeysWithValues: block.exercises.compactMap { exercise in
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
            Draft(movementName: "Thrusters", reps: 21, weight: "95 lb", restSeconds: 30),
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
        #expect(saved.blocks.count == 1)

        let block = try #require(saved.blocks.first)
        #expect(block.repeatTimes == 3)
        #expect(block.restAfterBlock == 60)
        #expect(block.exercises.count == 3)

        // SwiftData to-many relationships are unordered; look exercises up by movement name.
        let byName = exercisesByMovement(block)
        #expect(Set(byName.keys) == Set(["Thrusters", "Run", "Pull-up"]))
        #expect(Set(block.exercises.compactMap { $0.displayLabel })
                == Set(["21 Thrusters (95 lb)", "400 m Run", "100 Pull-ups"]))

        let thrusters = try #require(byName["Thrusters"])
        #expect(thrusters.displayLabel == "21 Thrusters (95 lb)")
        #expect(thrusters.reps == 21)
        #expect(thrusters.weight == "95 lb")
        #expect(thrusters.restSeconds == 30)

        let run = try #require(byName["Run"])
        #expect(run.displayLabel == "400 m Run")
        #expect(run.reps == nil)
        #expect(run.distance == "400 m")
        #expect(run.distanceUnit == "m")

        let pullUps = try #require(byName["Pull-up"])
        #expect(pullUps.displayLabel == "100 Pull-ups")
        #expect(pullUps.weight == nil)

        // Relationships set via property assignment resolve as inverses.
        for exercise in block.exercises {
            #expect(exercise.roundBlock == block)
        }
        #expect(block.workout == saved)
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

        let block = try #require(workout.blocks.first)
        #expect(block.repeatTimes == 0)
        #expect(block.restAfterBlock == nil)
        #expect(block.exercises.first?.displayLabel == "15 Air Squats")
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
        #expect(workout.blocks.first?.exercises.first?.movement == pullUps[0])
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
}
