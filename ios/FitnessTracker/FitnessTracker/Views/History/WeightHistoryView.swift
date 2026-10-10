import Charts
import SwiftUI

struct WeightHistoryView: View {
    /// When set, only the most recent `displayLimit` weigh-ins show, with a
    /// "More" link pushing an unrestricted instance of this same view -
    /// same recent-N-then-View-All pattern as `CardioHistoryView`.
    var displayLimit: Int? = 20

    @State private var logs: [BodyWeightLog] = []
    @State private var errorMessage: String?
    @State private var logToDelete: BodyWeightLog?
    private let repository = BodyWeightRepository()

    private var displayedLogs: [BodyWeightLog] {
        guard let displayLimit else { return logs }
        return Array(logs.prefix(displayLimit))
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            } else if logs.isEmpty {
                Text("No weigh-ins logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    WeightChartCard(logs: logs)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }
                .listRowBackground(AppRowBackground())

                ForEach(Array(displayedLogs.enumerated()), id: \.element.id) { index, log in
                    // Logs run newest first, so the gap is between this one
                    // and the next (older) one.
                    if index > 0, let gap = CheckinGaps.gap(between: log.loggedAt, and: displayedLogs[index - 1].loggedAt) {
                        gapRow(gap)
                    }
                    logRow(log)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                logToDelete = log
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                if let displayLimit, logs.count > displayLimit {
                    NavigationLink("More") {
                        WeightHistoryView(displayLimit: nil)
                    }
                }
            }
        }
        .appScreen()
        .navigationTitle("Weigh-Ins")
        .task { await load() }
        .confirmationDialog(
            "Delete this weigh-in? This can't be undone.",
            isPresented: Binding(get: { logToDelete != nil }, set: { if !$0 { logToDelete = nil } })
        ) {
            Button("Delete Weigh-In", role: .destructive) {
                if let log = logToDelete {
                    Task { await delete(log) }
                }
            }
        }
    }

    private func gapRow(_ gap: CheckinGaps.Gap) -> some View {
        let range = gap.days == 1
            ? gap.firstMissing.formatted(.dateTime.day().month(.abbreviated))
            : "\(gap.firstMissing.formatted(.dateTime.day().month(.abbreviated))) - \(gap.lastMissing.formatted(.dateTime.day().month(.abbreviated)))"
        return Label("\(gap.days) day\(gap.days == 1 ? "" : "s") with no weigh-in (\(range))", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(AppColor.warning)
    }

    @ViewBuilder
    private func logRow(_ log: BodyWeightLog) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.loggedAt, style: .date)
                    .font(.subheadline)
                if log.source != "manual" {
                    Text(log.source == "healthkit" ? "Apple Health" : log.source.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(String(format: "%.1f kg", log.weightKg))
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            logs = try await repository.fetchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ log: BodyWeightLog) async {
        do {
            try await repository.deleteLog(id: log.id)
            logs.removeAll { $0.id == log.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        logToDelete = nil
    }
}

/// Every weigh-in as a line, over a range you pick; drag across it to read a value.
private struct WeightChartCard: View {
    private enum Range: String, CaseIterable, Identifiable {
        case month = "4W", quarter = "3M", year = "1Y", all = "All"
        var id: String { rawValue }

        /// How far back it reaches, or nil for everything.
        var days: Int? {
            switch self {
            case .month: 28
            case .quarter: 91
            case .year: 365
            case .all: nil
            }
        }
    }

    /// Newest first, as the list has them.
    let logs: [BodyWeightLog]

    @State private var range: Range = .quarter
    @State private var selectedDate: Date?

    private var points: [BodyWeightLog] {
        let sorted = logs.sorted { $0.loggedAt < $1.loggedAt }
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return sorted }
        return sorted.filter { $0.loggedAt >= cutoff }
    }

    private var selected: BodyWeightLog? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.loggedAt.timeIntervalSince(selectedDate)) < abs($1.loggedAt.timeIntervalSince(selectedDate)) }
    }

    private var yDomain: ClosedRange<Double> {
        let weights = points.map(\.weightKg)
        guard let low = weights.min(), let high = weights.max() else { return 0...1 }
        return (low - 1)...(high + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let selected {
                    Text(String(format: "%.1f kg", selected.weightKg))
                        .font(.title3.bold())
                    Text(selected.loggedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let latest = points.last {
                    Text(String(format: "%.1f kg", latest.weightKg))
                        .font(.title3.bold())
                    if let first = points.first, points.count > 1 {
                        let change = latest.weightKg - first.weightKg
                        Text(String(format: "%+.1f kg", change))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if points.count < 2 {
                Text("Log a couple of weigh-ins to see the graph.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(points) { log in
                    LineMark(x: .value("Date", log.loggedAt), y: .value("Weight", log.weightKg))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(AppColor.weight)
                    PointMark(x: .value("Date", log.loggedAt), y: .value("Weight", log.weightKg))
                        .symbolSize(points.count > 60 ? 8 : 24)
                        .foregroundStyle(AppColor.weight)
                    if let selected, selected.id == log.id {
                        RuleMark(x: .value("Date", log.loggedAt))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXSelection(value: $selectedDate)
                .frame(height: 180)
            }

            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}
