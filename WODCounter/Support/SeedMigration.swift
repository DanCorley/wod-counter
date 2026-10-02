import Foundation
import SwiftData

enum SeedMigration {
    /// Bumped when a migration step is added below.
    private static let currentVersion = 2
    private static let versionKey = "seedMigrationVersion"

    static func applySeed(to container: ModelContainer) {
        let context = container.mainContext

        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.isBuiltin == true })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else {
            backfillSortIndexesIfNeeded(in: context)
            return
        }

        let cindy = BenchmarkSeed.cindy(in: context)
        let murph = BenchmarkSeed.murph(in: context)
        let fran = BenchmarkSeed.fran(in: context)
        let angie = BenchmarkSeed.angie(in: context)
        let grace = BenchmarkSeed.grace(in: context)
        let diane = BenchmarkSeed.diane(in: context)
        let helen = BenchmarkSeed.helen(in: context)
        let dt = BenchmarkSeed.dt(in: context)

        context.insert(cindy)
        context.insert(murph)
        context.insert(fran)
        context.insert(angie)
        context.insert(grace)
        context.insert(diane)
        context.insert(helen)
        context.insert(dt)

        try? context.save()
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }

    /// Gives `sortIndex` a real value on data written before the field existed.
    ///
    /// Built-ins are re-derived from `BenchmarkSeed`, which is authoritative —
    /// their stored array order is exactly what could not be trusted. Custom
    /// workouts have no such source, so their current array order is the best
    /// available evidence and is recorded as-is.
    private static func backfillSortIndexesIfNeeded(in context: ModelContext) {
        guard UserDefaults.standard.integer(forKey: versionKey) < currentVersion else { return }

        let canonical = BenchmarkSeed.canonicalPositions()

        let workouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        for workout in workouts {
            let positions = workout.isBuiltin ? canonical[workout.name] : nil

            for (blockIndex, block) in workout.blocks.enumerated() {
                var resolvedBlockIndex: Int?

                for (exerciseIndex, exercise) in block.exercises.enumerated() {
                    let label = exercise.displayLabel ?? exercise.movement?.name
                    if let positions, let label, let position = positions[label] {
                        exercise.sortIndex = position.exercise
                        // A block's position follows its exercises' labels,
                        // since the stored array order is the untrusted part.
                        resolvedBlockIndex = resolvedBlockIndex ?? position.block
                    } else {
                        exercise.sortIndex = exerciseIndex
                    }
                }

                block.sortIndex = resolvedBlockIndex ?? blockIndex
            }
        }

        try? context.save()
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }
}
