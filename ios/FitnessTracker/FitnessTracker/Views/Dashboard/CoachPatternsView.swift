import Charts
import SwiftUI

/// The adherence calendar and what it says about where days go wrong: a phase-long Monday-Sunday
/// grid, the conditions that predict an off day, and how long the off-plan stretches run.
struct CoachPatternsView: View {
    @ObservedObject var viewModel: CoachViewModel
    @State private var selected: CoachDayRecord?

    var body: some View {
        List {
            if let snapshot = viewModel.snapshot {
                tilesSection(snapshot)
                calendarSection(snapshot)
                weakSpotsSection(snapshot)
                slipChainsSection(snapshot)
            } else if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading your days...").foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            } else {
                Text(viewModel.errorMessage ?? "No active phase yet.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .appScreen()
        .navigationTitle("Adherence")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel.snapshot == nil { await viewModel.load() } }
        .refreshable { await viewModel.load() }
        .sheet(item: $selected) { record in
            DayDetailSheet(record: record)
                .presentationDetents([.medium])
        }
    }

    // MARK: Colours

    private func color(for record: CoachDayRecord) -> Color {
        switch record.status {
        case .on: AppColor.success
        case .flagged: AppColor.error
        case .over: AppColor.warning
        case .blank: Color.secondary.opacity(0.4)
        }
    }

    // MARK: Header tiles

    private func tilesSection(_ snapshot: CoachSnapshot) -> some View {
        let counts = snapshot.counts
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    tile(title: "On plan", value: "\(counts.on) of \(counts.total)", detail: "\(Int((counts.onShare * 100).rounded()))%")
                    if let last14 = viewModel.last14 {
                        tile(title: "Last 14 days", value: "\(last14.on) of \(last14.of)", detail: "on plan")
                    }
                    if let now = viewModel.trendNowKg, let start = viewModel.trendStartKg {
                        let change = now - start
                        tile(title: "Weight", value: String(format: "%.1f kg", now),
                             detail: (change < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(change)) + " since start")
                    }
                }
                if counts.off > 0 {
                    Text("Off plan: \(counts.flagged) flagged, \(counts.blank) barely logged, \(counts.over) over target")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func tile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).minimumScaleFactor(0.7).lineLimit(1)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Calendar

    private func calendarSection(_ snapshot: CoachSnapshot) -> some View {
        Section {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("").frame(width: 44)
                    ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { index in
                        Text(["M", "T", "W", "T", "F", "S", "S"][index])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    Text("").frame(width: 30)
                }
                ForEach(viewModel.weeks) { week in
                    HStack(spacing: 6) {
                        Text(week.monday.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        ForEach(week.cells) { cell in
                            cellView(cell)
                        }
                        Text("\(week.onCount)/7")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                legend
            }
            .padding(.vertical, 4)
        } header: {
            Text("Calendar")
        }
    }

    @ViewBuilder
    private func cellView(_ cell: CoachWeekCell) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        if let record = cell.record {
            Button { selected = record } label: {
                shape.fill(color(for: record))
                    .overlay {
                        if record.isSick { Circle().fill(.white.opacity(0.9)).frame(width: 6, height: 6) }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(cell.date.formatted(.dateTime.weekday(.wide).day().month())): \(record.status.displayName)\(record.isSick ? ", sick" : "")")
        } else {
            shape.strokeBorder(Color.secondary.opacity(cell.isToday ? 0.9 : 0.25), lineWidth: cell.isToday ? 2 : 1)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .opacity(isBeforePhase(cell) ? 0.15 : 1)
        }
    }

    private func isBeforePhase(_ cell: CoachWeekCell) -> Bool {
        guard let first = viewModel.snapshot?.days.first, let start = DateFormatting.date(fromISODate: first.date) else { return false }
        return cell.date < start
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(AppColor.success, "On")
            legendItem(AppColor.error, "Flagged")
            legendItem(Color.secondary.opacity(0.4), "Barely logged")
            legendItem(AppColor.warning, "Over")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }

    // MARK: Weak spots

    private struct Bar: Identifiable {
        let label: String
        let rate: Double
        let n: Int
        let weak: Bool
        var id: String { label }
    }

    private func bars(_ snapshot: CoachSnapshot) -> [Bar] {
        func bar(_ label: String, off: Int, n: Int, weak: Bool) -> Bar {
            Bar(label: label, rate: n == 0 ? 0 : Double(off) / Double(n), n: n, weak: weak)
        }
        var result: [Bar] = []
        if let slip = snapshot.condition(.afterSlip) {
            result.append(bar("After an on day", off: slip.restOff, n: slip.restN, weak: false))
            result.append(bar("After an off day", off: slip.off, n: slip.n, weak: snapshot.weakness(.afterSlip) != nil))
        }
        if let training = snapshot.condition(.noTraining) {
            result.append(bar("Trained", off: training.restOff, n: training.restN, weak: false))
            result.append(bar("No session", off: training.off, n: training.n, weak: snapshot.weakness(.noTraining) != nil))
        }
        for weakness in snapshot.weaknesses {
            switch weakness.kind {
            case .weekday, .highHunger:
                result.append(bar(weakness.label, off: weakness.off, n: weakness.n, weak: true))
            default: break
            }
        }
        return result
    }

    @ViewBuilder
    private func weakSpotsSection(_ snapshot: CoachSnapshot) -> some View {
        let data = bars(snapshot)
        if !data.isEmpty {
            Section {
                Chart {
                    ForEach(data) { bar in
                        BarMark(x: .value("Off plan", bar.rate), y: .value("Condition", bar.label))
                            .foregroundStyle(bar.weak ? AppColor.error : Color.secondary.opacity(0.5))
                            .annotation(position: .trailing) {
                                Text("\(Int((bar.rate * 100).rounded()))% \u{00b7} n=\(bar.n)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                    RuleMark(x: .value("Baseline", snapshot.baseline))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("all days \(Int((snapshot.baseline * 100).rounded()))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .chartXScale(domain: 0...1.25)
                .chartXAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v * 100))%") } }
                    }
                }
                .frame(height: CGFloat(data.count) * 38 + 40)
                Text("Share of days that went off plan. Red bars run 15 points or more above the rest, over at least 8 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Where days go wrong")
            }
        }
    }

    // MARK: Slip chains

    @ViewBuilder
    private func slipChainsSection(_ snapshot: CoachSnapshot) -> some View {
        if !snapshot.offRuns.isEmpty {
            Section {
                Chart(snapshot.offRuns) { run in
                    BarMark(x: .value("Started", run.start), y: .value("Days", run.length))
                        .foregroundStyle(run.length >= CoachEngine.roughStretchDays ? AppColor.error : AppColor.warning)
                        .annotation(position: .top) {
                            Text("\(run.length)").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .frame(height: 140)
                Text("Each bar is one stretch of off-plan days, oldest first. Longest: \(snapshot.longestOffRun) days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Slip chains")
            }
        }
    }
}

/// What a day looked like: calories, protein, whether you trained, and what you said about it.
private struct DayDetailSheet: View {
    let record: CoachDayRecord

    private var dateText: String {
        DateFormatting.date(fromISODate: record.date)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? record.date
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Result", record.status.displayName + (record.isSick ? " (sick)" : ""))
                    row("Calories", "\(Int(record.calories.rounded()).formatted()) of \(Int(record.target.rounded()).formatted()) kcal")
                    if let protein = record.proteinG { row("Protein", "\(Int(protein.rounded())) g") }
                    row("Workout", record.trained ? "Trained" : (record.scheduledTraining ? "Skipped" : "Rest day"))
                    if record.isTreatDay { row("Planned treat", "Yes") }
                }
                if let note = record.note {
                    Section("What you said") { Text(note) }
                }
            }
            .navigationTitle(dateText)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
