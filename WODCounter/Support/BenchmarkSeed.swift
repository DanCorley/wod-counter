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

    static func fran(in context: ModelContext) -> Workout {
        let workout = Workout(
            name: "Fran",
            workoutDescription: "21-15-9 Thrusters and Pull-ups",
            category: "Girl",
            mode: .topTime,
            isBuiltin: true
        )

        let thrusters = makeMovement(name: "Thrusters", equipment: "Barbell", category: "Power", in: context)
        let pullUps = makeMovement(name: "Pull-up", equipment: "Bar", category: "Gymnastics", in: context)

        let block21 = RoundBlock(repeatTimes: 1)
        block21.exercises = [
            makeExercise(movement: thrusters, reps: 21, weight: "95 lb", displayLabel: "21 Thrusters (95 lb)", in: context),
            makeExercise(movement: pullUps, reps: 21, displayLabel: "21 Pull-ups", in: context),
        ]

        let block15 = RoundBlock(repeatTimes: 1)
        block15.exercises = [
            makeExercise(movement: thrusters, reps: 15, weight: "95 lb", displayLabel: "15 Thrusters (95 lb)", in: context),
            makeExercise(movement: pullUps, reps: 15, displayLabel: "15 Pull-ups", in: context),
        ]

        let block9 = RoundBlock(repeatTimes: 1)
        block9.exercises = [
            makeExercise(movement: thrusters, reps: 9, weight: "95 lb", displayLabel: "9 Thrusters (95 lb)", in: context),
            makeExercise(movement: pullUps, reps: 9, displayLabel: "9 Pull-ups", in: context),
        ]

        workout.blocks = [block21, block15, block9]
        return workout
    }

    static func angie(in context: ModelContext) -> Workout {
        let workout = Workout(
            name: "Angie",
            workoutDescription: "For time: 100 pull-ups, 100 push-ups, 100 sit-ups, 100 air squats",
            category: "Girl",
            mode: .topTime,
            isBuiltin: true
        )

        let pullUps = makeMovement(name: "Pull-up", equipment: "Bar", category: "Gymnastics", in: context)
        let pushUps = makeMovement(name: "Push-up", equipment: "Bodyweight", category: "Gymnastics", in: context)
        let sitUps = makeMovement(name: "Sit-up", equipment: "Bodyweight", category: "Gymnastics", in: context)
        let squats = makeMovement(name: "Air Squat", equipment: "Bodyweight", category: "Gymnastics", in: context)

        let block = RoundBlock(repeatTimes: 1)
        block.exercises = [
            makeExercise(movement: pullUps, reps: 100, displayLabel: "100 Pull-ups", in: context),
            makeExercise(movement: pushUps, reps: 100, displayLabel: "100 Push-ups", in: context),
            makeExercise(movement: sitUps, reps: 100, displayLabel: "100 Sit-ups", in: context),
            makeExercise(movement: squats, reps: 100, displayLabel: "100 Air Squats", in: context),
        ]

        workout.blocks = [block]
        return workout
    }

    static func grace(in context: ModelContext) -> Workout {
        let workout = Workout(
            name: "Grace",
            workoutDescription: "For time: 30 Clean & Jerks",
            category: "Girl",
            mode: .topTime,
            isBuiltin: true
        )

        let cleanJerk = makeMovement(name: "Clean & Jerk", equipment: "Barbell", category: "Strength", in: context)

        let block = RoundBlock(repeatTimes: 1)
        block.exercises = [
            makeExercise(movement: cleanJerk, reps: 30, weight: "135 lb", displayLabel: "30 Clean & Jerk (135 lb)", in: context),
        ]

        workout.blocks = [block]
        return workout
    }

    static func diane(in context: ModelContext) -> Workout {
        let workout = Workout(
            name: "Diane",
            workoutDescription: "21-15-9 Deadlifts and Handstand Push-ups",
            category: "Girl",
            mode: .topTime,
            isBuiltin: true
        )

        let deadlifts = makeMovement(name: "Deadlift", equipment: "Barbell", category: "Strength", in: context)
        let hspu = makeMovement(name: "Handstand Push-up", equipment: "Bodyweight", category: "Gymnastics", in: context)

        let block21 = RoundBlock(repeatTimes: 1)
        block21.exercises = [
            makeExercise(movement: deadlifts, reps: 21, weight: "225 lb", displayLabel: "21 Deadlifts (225 lb)", in: context),
            makeExercise(movement: hspu, reps: 21, displayLabel: "21 Handstand Push-ups", in: context),
        ]

        let block15 = RoundBlock(repeatTimes: 1)
        block15.exercises = [
            makeExercise(movement: deadlifts, reps: 15, weight: "225 lb", displayLabel: "15 Deadlifts (225 lb)", in: context),
            makeExercise(movement: hspu, reps: 15, displayLabel: "15 Handstand Push-ups", in: context),
        ]

        let block9 = RoundBlock(repeatTimes: 1)
        block9.exercises = [
            makeExercise(movement: deadlifts, reps: 9, weight: "225 lb", displayLabel: "9 Deadlifts (225 lb)", in: context),
            makeExercise(movement: hspu, reps: 9, displayLabel: "9 Handstand Push-ups", in: context),
        ]

        workout.blocks = [block21, block15, block9]
        return workout
    }

    static func helen(in context: ModelContext) -> Workout {
        let workout = Workout(
            name: "Helen",
            workoutDescription: "3 rounds for time: 400m run, 21 KB swings, 12 pull-ups",
            category: "Girl",
            mode: .topTime,
            isBuiltin: true
        )

        let run = makeMovement(name: "Run", equipment: "Track", category: "Cardio", in: context)
        let kbSwings = makeMovement(name: "Kettlebell Swing", equipment: "Kettlebell", category: "Power", in: context)
        let pullUps = makeMovement(name: "Pull-up", equipment: "Bar", category: "Gymnastics", in: context)

        let block = RoundBlock(repeatTimes: 3)
        block.exercises = [
            makeExercise(movement: run, reps: nil, distance: "400 m", distanceUnit: "m", displayLabel: "400 m Run", in: context),
            makeExercise(movement: kbSwings, reps: 21, weight: "53/35 lb", displayLabel: "21 Kettlebell Swings (53/35 lb)", in: context),
            makeExercise(movement: pullUps, reps: 12, displayLabel: "12 Pull-ups", in: context),
        ]

        workout.blocks = [block]
        return workout
    }

    static func dt(in context: ModelContext) -> Workout {
        let workout = Workout(
            name: "DT",
            workoutDescription: "5 rounds for time: 12 deadlifts, 9 hang power cleans, 6 push jerks",
            category: "Hero",
            mode: .topTime,
            isBuiltin: true
        )

        let deadlifts = makeMovement(name: "Deadlift", equipment: "Barbell", category: "Strength", in: context)
        let hangPowerCleans = makeMovement(name: "Hang Power Clean", equipment: "Barbell", category: "Power", in: context)
        let pushJerks = makeMovement(name: "Push Jerk", equipment: "Barbell", category: "Power", in: context)

        let block = RoundBlock(repeatTimes: 5)
        block.exercises = [
            makeExercise(movement: deadlifts, reps: 12, weight: "225 lb", displayLabel: "12 Deadlifts (225 lb)", in: context),
            makeExercise(movement: hangPowerCleans, reps: 9, weight: "155 lb", displayLabel: "9 Hang Power Cleans (155 lb)", in: context),
            makeExercise(movement: pushJerks, reps: 6, weight: "155 lb", displayLabel: "6 Push Jerks (155 lb)", in: context),
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

    private static func makeExercise(movement: Movement, reps: Int?, weight: String? = nil,
                                     distance: String? = nil, distanceUnit: String? = nil,
                                     displayLabel: String, in context: ModelContext) -> Exercise {
        let exercise = Exercise(movement: movement, reps: reps, weight: weight,
                                distance: distance, distanceUnit: distanceUnit,
                                displayLabel: displayLabel)
        context.insert(exercise)
        return exercise
    }
}
