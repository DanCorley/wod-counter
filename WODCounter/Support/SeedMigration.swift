import Foundation
import SwiftData

enum SeedMigration {
    static func applySeed(to container: ModelContainer) {
        let context = container.mainContext

        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.isBuiltin == true })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

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
    }
}
