import XCTest
import SwiftData
@testable import WODCounter

final class WODSimulatorTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        container = Container.inMemory()
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Cindy (AMRAP For-Time)
    @MainActor
    func testCindyAMRAPLoopsUntilClockOrExpiry() {
        let cindy = BenchmarkSeed.cindy(context: context)
        var sim = WODSimulator(workout: cindy)

        XCTAssertEqual(sim.phase, .idle)
        XCTAssertEqual(sim.roundsCompleted, 0)
        XCTAssertEqual(sim.currentRepProgress, 0)

        sim.start()
        XCTAssertEqual(sim.phase, .running)

        // Pull-ups: 5 reps
        for i in 1...5 {
            let event = sim.advanceRep()
            if i < 5 {
                XCTAssertEqual(event, .none)
                XCTAssertEqual(sim.exerciseIndex, 0)
            } else {
                // Moving to push-ups
                XCTAssertEqual(sim.exerciseIndex, 1)
                XCTAssertEqual(sim.currentRepProgress, 0)
            }
        }

        // Push-ups: 10 reps
        for i in 1...10 {
            let event = sim.advanceRep()
            if i < 10 {
                XCTAssertEqual(event, .none)
                XCTAssertEqual(sim.exerciseIndex, 1)
            } else {
                // Moving to air squats
                XCTAssertEqual(sim.exerciseIndex, 2)
                XCTAssertEqual(sim.currentRepProgress, 0)
            }
        }

        // Air Squats: 15 reps -> completes Round 1
        for i in 1...15 {
            let event = sim.advanceRep()
            if i < 15 {
                XCTAssertEqual(event, .none)
                XCTAssertEqual(sim.exerciseIndex, 2)
            } else {
                XCTAssertEqual(event, .blockCompleted)
                XCTAssertEqual(sim.roundsCompleted, 1)
                XCTAssertEqual(sim.exerciseIndex, 0) // Loops back to pull-ups
                XCTAssertEqual(sim.phase, .running) // Stays running because AMRAP
            }
        }

        // Second round (another 30 reps)
        for _ in 1...30 {
            _ = sim.advanceRep()
        }
        XCTAssertEqual(sim.roundsCompleted, 2)
        XCTAssertEqual(sim.phase, .running)

        // Advance active time past 20 minutes (1200 seconds)
        sim.advanceTime(1201, active: true)
        XCTAssertTrue(sim.isClockExpired)
        XCTAssertEqual(sim.phase, .finished)
    }

    // MARK: - Murph (Single-Block Top-Time Auto-Stop)
    @MainActor
    func testMurphTopTimeAutoStopsOnFinalRep() {
        let murph = BenchmarkSeed.murph(context: context)
        var sim = WODSimulator(workout: murph)

        sim.start()

        // 100 Pull-ups
        for _ in 1...100 {
            _ = sim.advanceRep()
        }
        XCTAssertEqual(sim.exerciseIndex, 1)

        // 200 Push-ups
        for _ in 1...200 {
            _ = sim.advanceRep()
        }
        XCTAssertEqual(sim.exerciseIndex, 2)

        // 299 Air Squats
        for _ in 1...299 {
            let event = sim.advanceRep()
            XCTAssertEqual(event, .none)
            XCTAssertEqual(sim.phase, .running)
        }

        // Final 300th rep -> Auto-Stop!
        let finalEvent = sim.advanceRep()
        XCTAssertEqual(finalEvent, .finished(.goalReached))
        XCTAssertEqual(sim.roundsCompleted, 1)
        XCTAssertEqual(sim.phase, .finished)
        XCTAssertTrue(sim.canAutoStop)
    }

    // MARK: - Fran (Multi-Block Descending Scheme: 21-15-9)
    @MainActor
    func testFran3BlocksDescendingAutoStops() {
        let fran = BenchmarkSeed.fran(context: context)
        var sim = WODSimulator(workout: fran)

        XCTAssertEqual(fran.blocks.count, 3)
        sim.start()

        // Block 1 (21 Thrusters + 21 Pull-ups)
        for _ in 1...42 {
            _ = sim.advanceRep()
        }
        XCTAssertEqual(sim.roundsCompleted, 1)
        XCTAssertEqual(sim.blockIndex, 1) // Moves to 15s block
        XCTAssertEqual(sim.phase, .running)

        // Block 2 (15 Thrusters + 15 Pull-ups)
        for _ in 1...30 {
            _ = sim.advanceRep()
        }
        XCTAssertEqual(sim.roundsCompleted, 2)
        XCTAssertEqual(sim.blockIndex, 2) // Moves to 9s block
        XCTAssertEqual(sim.phase, .running)

        // Block 3 (9 Thrusters + 9 Pull-ups)
        for _ in 1...17 {
            _ = sim.advanceRep()
        }
        XCTAssertEqual(sim.phase, .running)

        // Final 18th rep of 9s block -> Auto-stop
        let event = sim.advanceRep()
        XCTAssertEqual(event, .finished(.goalReached))
        XCTAssertEqual(sim.roundsCompleted, 3)
        XCTAssertEqual(sim.phase, .finished)
    }

    // MARK: - DT (Single-Block Repeat: 5 Rounds)
    @MainActor
    func testDT5RoundsAutoStops() {
        let dt = BenchmarkSeed.dt(context: context)
        var sim = WODSimulator(workout: dt)

        sim.start()
        let repsPerRound = 12 + 9 + 6 // 27 reps per round

        for round in 1...4 {
            for _ in 1...repsPerRound {
                _ = sim.advanceRep()
            }
            XCTAssertEqual(sim.roundsCompleted, round)
            XCTAssertEqual(sim.phase, .running)
        }

        // 5th round
        for _ in 1...(repsPerRound - 1) {
            _ = sim.advanceRep()
        }
        XCTAssertEqual(sim.phase, .running)

        let finalEvent = sim.advanceRep()
        XCTAssertEqual(finalEvent, .finished(.goalReached))
        XCTAssertEqual(sim.roundsCompleted, 5)
        XCTAssertEqual(sim.phase, .finished)
    }

    // MARK: - Distanced-Only Exercises (Effective Rep Quota = 1)
    @MainActor
    func testDistancedOnlyExerciseHasEffectiveRepsOne() {
        let helen = BenchmarkSeed.helen(context: context)
        var sim = WODSimulator(workout: helen)

        sim.start()

        // 400m run is exercise 0 (reps is nil)
        XCTAssertNil(sim.currentExercise?.reps)
        XCTAssertEqual(sim.currentEffectiveReps, 1)

        // Advancing 1 rep completes the 400m run
        let event = sim.advanceRep()
        XCTAssertEqual(event, .none)
        XCTAssertEqual(sim.exerciseIndex, 1) // Moved to KB swings (21 reps)
    }

    // MARK: - Pause & Active Time Calculation
    @MainActor
    func testPauseFreezesActiveTimeAndAccumulatesPausedTime() {
        let cindy = BenchmarkSeed.cindy(context: context)
        var sim = WODSimulator(workout: cindy)

        sim.start()
        sim.advanceTime(20, active: true)
        XCTAssertEqual(sim.resultActiveTime, 20)
        XCTAssertEqual(sim.wallClock, 20)

        // Pause for 15 seconds
        sim.pause()
        XCTAssertEqual(sim.phase, .paused)
        sim.advanceTime(15, active: false)

        XCTAssertEqual(sim.resultActiveTime, 20)
        XCTAssertEqual(sim.wallClock, 35)

        // Resume and advance 10 active seconds
        sim.resume()
        XCTAssertEqual(sim.phase, .running)
        sim.advanceTime(10, active: true)

        XCTAssertEqual(sim.resultActiveTime, 30)
        XCTAssertEqual(sim.wallClock, 45)
    }

    // MARK: - Manual Finish
    @MainActor
    func testManualFinishEndsWorkout() {
        let cindy = BenchmarkSeed.cindy(context: context)
        var sim = WODSimulator(workout: cindy)

        sim.start()
        for _ in 1...15 {
            _ = sim.advanceRep()
        }

        let event = sim.finish()
        XCTAssertEqual(event, .finished(.manual))
        XCTAssertEqual(sim.phase, .finished)
        XCTAssertEqual(sim.snapshot.isFinished, true)
    }
}
