import SwiftUI
import SwiftData
import Charts

// MARK: - Window

enum ResultsWindow: String, CaseIterable, Identifiable {
    case sevenDays  = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case allTime    = "All"

    var id: String { rawValue }

    /// The one `UserDefaults` key for the saved default window. Settings and
    /// History both go through this, and both tag their pickers with
    /// `rawValue` — previously each spelled its own key and its own tag
    /// strings, so the Settings picker silently controlled nothing.
    static let defaultsKey = "defaultResultsWindow"

    static let fallback: ResultsWindow = .thirtyDays

    /// Resolves a stored raw value, tolerating anything unrecognised.
    init(stored: String) {
        self = ResultsWindow(rawValue: stored) ?? Self.fallback
    }

    var dateInterval: DateInterval? {
        let now = Date()
        switch self {
        case .sevenDays:  return DateInterval(start: Calendar.current.date(byAdding: .day, value: -7, to: now)!, end: now)
        case .thirtyDays: return DateInterval(start: Calendar.current.date(byAdding: .day, value: -30, to: now)!, end: now)
        case .ninetyDays: return DateInterval(start: Calendar.current.date(byAdding: .day, value: -90, to: now)!, end: now)
        case .allTime:    return nil
        }
    }

    var label: String {
        switch self {
        case .sevenDays:  return "Past 7 days"
        case .thirtyDays: return "Past 30 days"
        case .ninetyDays: return "Past 90 days"
        case .allTime:    return "All time"
        }
    }
}

// MARK: - ResultsView

struct ResultsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.name) private var workouts: [Workout]
    @AppStorage(ResultsWindow.defaultsKey) private var storedWindow: String = ResultsWindow.fallback.rawValue

    private var selectedWindow: ResultsWindow {
        ResultsWindow(stored: storedWindow)
    }

    private var service: ResultsService {
        ResultsService(context: context)
    }

    /// Every record in the window, fetched once and grouped by workout.
    ///
    /// Previously each row re-fetched the whole `WorkoutRecord` table through a
    /// computed property, and several properties per row each triggered another
    /// one — so a scroll cost hundreds of full-table fetches. One fetch here,
    /// handed down to the rows, removes that entirely.
    private var recordsByWorkout: [PersistentIdentifier: [WorkoutRecord]] {
        Dictionary(
            grouping: service.history(window: selectedWindow.dateInterval)
                .filter { $0.workout != nil },
            by: { $0.workout!.persistentModelID }
        )
    }

    private var windowSummary: WindowSummary {
        service.summary(window: selectedWindow.dateInterval)
    }

    var body: some View {
        List {
            // Window Picker
            Section {
                Picker("Window", selection: Binding(
                    get: { selectedWindow },
                    set: { storedWindow = $0.rawValue }
                )) {
                    ForEach(ResultsWindow.allCases) { window in
                        Text(window.rawValue).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Summary Banner
            Section {
                SummaryBannerView(window: selectedWindow, summary: windowSummary)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Per-WOD Bests
            let grouped = recordsByWorkout
            let withHistory = workouts.filter { grouped[$0.persistentModelID]?.isEmpty == false }

            if withHistory.isEmpty {
                Section {
                    EmptyResultsView(window: selectedWindow)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("Personal Bests") {
                    ForEach(withHistory) { workout in
                        NavigationLink {
                            WODAttemptsView(workout: workout, window: selectedWindow)
                        } label: {
                            WODBestRow(
                                workout: workout,
                                records: grouped[workout.persistentModelID] ?? []
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("History")
    }
}

// MARK: - Summary Banner

private struct SummaryBannerView: View {
    let window: ResultsWindow
    let summary: WindowSummary

    var body: some View {
        HStack(spacing: 0) {
            SummaryStatView(value: "\(summary.workoutsCount)", label: "Workouts")
            Divider().frame(height: 40)
            SummaryStatView(value: "\(summary.prsThisWindow)", label: "PRs")
            if summary.workoutsCount > 0 {
                Divider().frame(height: 40)
                SummaryStatView(
                    value: Format.duration(summary.avgActiveTime),
                    label: "Avg Active"
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct SummaryStatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Per-WOD Best Row

private struct WODBestRow: View {
    let workout: Workout
    /// Handed in already fetched — see `ResultsView.recordsByWorkout`.
    let records: [WorkoutRecord]

    /// Only comparable efforts are ranked — an abandoned attempt's fast time is
    /// not a result. Mirrors `ResultsService.best(for:)` over the slice this
    /// row was handed.
    private var rankedRecords: [WorkoutRecord] {
        records.filter(\.isRankable)
    }

    private var bestRecord: WorkoutRecord? {
        if workout.mode == .forTime {
            return rankedRecords.max(by: { $0.roundsCompleted < $1.roundsCompleted })
        } else {
            return rankedRecords.min(by: { $0.activeTime < $1.activeTime })
        }
    }

    private var bestMetric: String {
        guard let best = bestRecord else { return "—" }
        return workout.mode == .forTime
            ? "\(best.roundsCompleted) rds"
            : Format.duration(best.activeTime)
    }

    private var deltaText: String? {
        guard rankedRecords.count >= 2, let best = bestRecord else { return nil }

        // Second-best attempt (excluding the best record itself)
        let others = rankedRecords.filter { $0.id != best.id }

        if workout.mode == .forTime {
            guard let prevBest = others.max(by: { $0.roundsCompleted < $1.roundsCompleted }) else { return nil }
            let delta = best.roundsCompleted - prevBest.roundsCompleted
            if delta == 0 { return "=" }
            return delta > 0 ? "+\(delta) rds" : "\(delta) rds"
        } else {
            guard let prevBest = others.min(by: { $0.activeTime < $1.activeTime }) else { return nil }
            let delta = prevBest.activeTime - best.activeTime
            if abs(delta) < 1 { return "=" }
            let sign = delta > 0 ? "−" : "+"
            return "\(sign)\(Format.duration(abs(delta)))"
        }
    }

    private var deltaColor: Color {
        guard let text = deltaText, text != "=" else { return .secondary }
        // For for-time: "+" is improvement. For top-time: "−" (faster) is improvement.
        if workout.mode == .forTime {
            return text.hasPrefix("+") ? .green : .red
        } else {
            return text.hasPrefix("−") ? .green : .red
        }
    }

    private var hasPR: Bool {
        records.contains(where: { $0.isPR })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workout.name)
                    .font(.headline)
                if hasPR {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                Spacer()
                WorkoutModeBadge(mode: workout.mode)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bestMetric)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                if let delta = deltaText {
                    Text("(\(delta))")
                        .font(.subheadline.bold())
                        .foregroundStyle(deltaColor)
                }

                Spacer()

                Text("\(records.count) attempt\(records.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State

private struct EmptyResultsView: View {
    let window: ResultsWindow

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No results yet")
                .font(.title3.bold())
            Text("Complete workout sessions to see your history and personal records here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - WOD Attempts Drill-Down

struct WODAttemptsView: View {
    let workout: Workout
    let window: ResultsWindow

    @Environment(\.modelContext) private var context
    @State private var pendingDeletion: [WorkoutRecord] = []

    private var service: ResultsService {
        ResultsService(context: context)
    }

    private var records: [WorkoutRecord] {
        service.history(for: workout, window: window.dateInterval)
    }

    /// Points for the best-over-time bar chart: (date, metric value).
    private var chartData: [(date: Date, value: Double)] {
        // Progression only means something across comparable efforts: an
        // abandoned attempt would plot as a sudden, misleading improvement.
        records
            .filter(\.isRankable)
            .sorted(by: { $0.date < $1.date })
            .map { record in
                let value = workout.mode == .forTime
                    ? Double(record.roundsCompleted)
                    : record.activeTime
                return (date: record.date, value: value)
            }
    }

    private var chartYLabel: String {
        workout.mode == .forTime ? "Rounds" : "Active Time (s)"
    }

    var body: some View {
        List {
            // Progress chart (only when ≥ 2 records)
            if chartData.count >= 2 {
                Section("Progression") {
                    Chart(chartData, id: \.date) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value(chartYLabel, point.value)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(4)
                    }
                    .frame(height: 160)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .padding(.vertical, 8)
                }
            }

            // Individual attempt cards
            Section("Attempts") {
                ForEach(records) { record in
                    AttemptCardRow(record: record, workout: workout)
                }
                .onDelete { offsets in
                    pendingDeletion = offsets.map { records[$0] }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { EditButton() }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Delete this attempt?" : "Delete \(pendingDeletion.count) attempts?",
            isPresented: Binding(
                get: { !pendingDeletion.isEmpty },
                set: { if !$0 { pendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDeletion() }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text(pendingDeletion.contains(where: \.isPR)
                 ? "This includes a personal record. Your next-best attempt will become the PR."
                 : "This can't be undone.")
        }
    }

    private func confirmDeletion() {
        for record in pendingDeletion {
            context.delete(record)
        }
        pendingDeletion = []

        do {
            try context.save()
            // A deleted PR must not leave the workout with no record starred,
            // and deleting a weak attempt must not leave a later one wrongly
            // unstarred — so re-rank what remains.
            service.recomputePRs(for: workout)
            try context.save()
        } catch {
            context.rollback()
        }
    }
}

// MARK: - Individual Attempt Row

private struct AttemptCardRow: View {
    let record: WorkoutRecord
    let workout: Workout

    @State private var shareImage: Image?

    var body: some View {
        VStack(spacing: 0) {
            ResultsCardView(record: record, workout: workout)
                .padding(.vertical, 8)

            HStack {
                Spacer()
                if let shareImage {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview(shareTitle, image: shareImage)
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.accentColor)
                } else {
                    // Placeholder while the card rasterises, so the row's
                    // height doesn't jump when the control appears.
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        // Rasterise once, when the row first appears. This used to be a
        // computed property that ShareLink evaluated twice on every render
        // pass — two full-size images per row per pass, on the main thread.
        // The @State also dies with the row, so offscreen cards aren't retained.
        .task {
            if shareImage == nil {
                shareImage = renderCard()
            }
        }
    }

    private var shareTitle: String {
        "\(workout.name) — \(record.date.formatted(date: .abbreviated, time: .omitted))"
    }

    @MainActor
    private func renderCard() -> Image? {
        let renderer = ImageRenderer(
            content: ResultsCardView(record: record, workout: workout)
                .frame(width: 320)
                .padding()
                .background(Color(.systemBackground))
        )
        // 2x is plenty for a shared image and roughly halves the bitmap's
        // memory against the previous 3x.
        renderer.scale = 2
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
