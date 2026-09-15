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
        context.insert(cindy)
        context.insert(murph)

        try? context.save()
    }
}
