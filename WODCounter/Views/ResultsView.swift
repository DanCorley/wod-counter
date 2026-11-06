import SwiftUI
import SwiftData
import Charts

// MARK: - ResultsView

struct ResultsView: View {
    @Query(sort: \Workout.name) private var workouts: [Workout]
    // Observing records directly is the refresh path for newly saved attempts.
    @Query(sort: [SortDescriptor(\WorkoutRecord.date, order: .reverse)]) private var records: [WorkoutRecord]
    @AppStorage(ResultsWindow.storageKey) private var storedWindow: String = ResultsWindow.defaultValue.rawValue

    private var selectedWindow: ResultsWindow {
        ResultsWindow(storedValue: storedWindow)
    }

    /// Records for the selected window, filtered once per render.
    private var windowRecords: [WorkoutRecord] {
        ResultsService.filter(records, window: selectedWindow.dateInterval)
    }

    /// Workouts with at least one record in the selected window, grouped from one fetch.
    private func bestRows(for records: [WorkoutRecord]) -> [WorkoutBestRowData] {
        let workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.persistentModelID, $0) })
        return ResultsService.bestSummaries(from: records).compactMap { summary in
            workoutsByID[summary.workoutID].map { WorkoutBestRowData(workout: $0, summary: summary) }
        }
    }

    var body: some View {
        let currentRecords = windowRecords
        let summary = ResultsService.summary(from: currentRecords)
        let rows = bestRows(for: currentRecords)

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
                SummaryBannerView(window: selectedWindow, summary: summary)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Per-WOD Bests
            if rows.isEmpty {
                Section {
                    EmptyResultsView(window: selectedWindow)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("Personal Bests") {
                    ForEach(rows) { row in
                        NavigationLink {
                            WODAttemptsView(workout: row.workout, window: selectedWindow)
                        } label: {
                            WODBestRow(summary: row.summary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("History")
    }
}

// MARK: - Row Data

private struct WorkoutBestRowData: Identifiable {
    let workout: Workout
    let summary: WorkoutBestSummary

    var id: PersistentIdentifier { summary.workoutID }
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
    let summary: WorkoutBestSummary

    private var deltaColor: Color {
        guard let delta = summary.delta else { return .secondary }
        switch delta {
        case .equal:
            return .secondary
        case .regressed:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.workoutName)
                    .font(.headline)
                if summary.hasPR {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                Spacer()
                WorkoutModeBadge(mode: summary.mode)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.bestMetricText)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                if let delta = summary.delta {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(delta.text(for: summary.mode))
                            .font(.subheadline.bold())
                            .foregroundStyle(deltaColor)
                        Text("vs last")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(delta.text(for: summary.mode)) versus last attempt")
                }

                Spacer()

                Text("\(summary.attemptCount) attempt\(summary.attemptCount == 1 ? "" : "s")")
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

    // A record insert refreshes this drill-down without relying on the parent view.
    @Query(sort: [SortDescriptor(\WorkoutRecord.date, order: .reverse)]) private var allRecords: [WorkoutRecord]

    private var records: [WorkoutRecord] {
        ResultsService.filter(allRecords, workout: workout, window: window.dateInterval)
    }

    private var chartYLabel: String {
        workout.mode == .forTime ? "Rounds" : "Active Time (s)"
    }

    var body: some View {
        let attempts = records
        let chartPoints = ResultsService.bestSeries(from: attempts, mode: workout.mode)

        List {
            // Progression chart (only when at least two bests exist)
            if chartPoints.count >= 2 {
                Section("Best Progression") {
                    Chart(chartPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(chartYLabel, point.value)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(Color.accentColor)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(chartYLabel, point.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(30)
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
                ForEach(attempts) { record in
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
