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
    @AppStorage("defaultResultsWindow") private var storedWindow: String = ResultsWindow.thirtyDays.rawValue

    private var selectedWindow: ResultsWindow {
        ResultsWindow(rawValue: storedWindow) ?? .thirtyDays
    }

    private var service: ResultsService {
        ResultsService(context: context)
    }

    private var windowSummary: WindowSummary {
        service.summary(window: selectedWindow.dateInterval)
    }

    /// Workouts that have at least one record in the selected window.
    private var workoutsWithHistory: [Workout] {
        workouts.filter { workout in
            !service.history(for: workout, window: selectedWindow.dateInterval).isEmpty
        }
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
            if workoutsWithHistory.isEmpty {
                Section {
                    EmptyResultsView(window: selectedWindow)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("Personal Bests") {
                    ForEach(workoutsWithHistory) { workout in
                        NavigationLink {
                            WODAttemptsView(workout: workout, window: selectedWindow)
                        } label: {
                            WODBestRow(
                                workout: workout,
                                window: selectedWindow,
                                service: service
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
    let window: ResultsWindow
    let service: ResultsService

    private var records: [WorkoutRecord] {
        service.history(for: workout, window: window.dateInterval)
    }

    private var bestRecord: WorkoutRecord? {
        if workout.mode == .forTime {
            return records.max(by: { $0.roundsCompleted < $1.roundsCompleted })
        } else {
            return records.min(by: { $0.activeTime < $1.activeTime })
        }
    }

    private var bestMetric: String {
        guard let best = bestRecord else { return "—" }
        return workout.mode == .forTime
            ? "\(best.roundsCompleted) rds"
            : Format.duration(best.activeTime)
    }

    private var deltaText: String? {
        guard records.count >= 2, let best = bestRecord else { return nil }

        // Second-best attempt (excluding the best record itself)
        let others = records.filter { $0.id != best.id }

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

    private var service: ResultsService {
        ResultsService(context: context)
    }

    private var records: [WorkoutRecord] {
        service.history(for: workout, window: window.dateInterval)
    }

    /// Points for the best-over-time bar chart: (date, metric value).
    private var chartData: [(date: Date, value: Double)] {
        records
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
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.large)
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
                ShareLink(
                    item: renderedCard,
                    preview: SharePreview(
                        "\(workout.name) — \(record.date.formatted(date: .abbreviated, time: .omitted))",
                        image: renderedCard
                    )
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
    }

    @MainActor
    private var renderedCard: Image {
        let renderer = ImageRenderer(
            content: ResultsCardView(record: record, workout: workout)
                .frame(width: 320)
                .padding()
                .background(Color(.systemBackground))
        )
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}
