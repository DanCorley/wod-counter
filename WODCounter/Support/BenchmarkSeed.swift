import Foundation
import SwiftData

enum BenchmarkSeed {
    static func cindy(in context: ModelContext) -> Workout {
        let workout = Workout(
            name: "Cindy",
            workoutDescription: "Complete as many rounds as possible in 20 minutes",
            category: "Girl",
            mode: .forTime,
            isBuiltin: true,
            forTimeMinutes: 20
        )

        let pullUps = makeMovement(name: "Pull-up", equipment: "Bar", category: "Gymnastics", in: context)
        let pushUps = makeMovement(name: "Push-up", equipment: "Bodyweight", category: "Gymnastics", in: context)
        let squats = makeMovement(name: "Air Squat", equipment: "Bodyweight", category: "Gymnastics", in: context)

        let block = RoundBlock(repeatTimes: 0)
        block.exercises = [
            makeExercise(movement: pullUps, reps: 5, displayLabel: "5 Pull-ups", in: context),
            makeExercise(movement: pushUps, reps: 10, displayLabel: "10 Push-ups", in: context),
            makeExercise(movement: squats, reps: 15, displayLabel: "15 Air Squats", in: context),
        ]

        workout.blocks = [block]
        return workout
    }

    static func murph(in context: ModelContext) -> Workout {
        let workout = Workout(
            name: "Murph",
            workoutDescription: "For time: 100 pull-ups, 200 push-ups, 300 squats",
            category: "Hero",
            mode: .topTime,
            isBuiltin: true
        )

        let pullUps = makeMovement(name: "Pull-up", equipment: "Bar", category: "Gymnastics", in: context)
        let pushUps = makeMovement(name: "Push-up", equipment: "Bodyweight", category: "Gymnastics", in: context)
        let squats = makeMovement(name: "Air Squat", equipment: "Bodyweight", category: "Gymnastics", in: context)

        let block = RoundBlock(repeatTimes: 1)
        block.exercises = [
            makeExercise(movement: pullUps, reps: 100, displayLabel: "100 Pull-ups", in: context),
            makeExercise(movement: pushUps, reps: 200, displayLabel: "200 Push-ups", in: context),
            makeExercise(movement: squats, reps: 300, displayLabel: "300 Air Squats", in: context),
        ]

        workout.blocks = [block]
        return workout
    }

    private static func makeMovement(name: String, equipment: String?, category: String?,
                                     in context: ModelContext) -> Movement {
        let descriptor = FetchDescriptor<Movement>(predicate: #Predicate { $0.name == name })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let movement = Movement(name: name, equipment: equipment, category: category)
        context.insert(movement)
        return movement
    }

    private static func makeExercise(movement: Movement, reps: Int, displayLabel: String,
                                     in context: ModelContext) -> Exercise {
        let exercise = Exercise(movement: movement, reps: reps, displayLabel: displayLabel)
        context.insert(exercise)
        return exercise
    }
}
