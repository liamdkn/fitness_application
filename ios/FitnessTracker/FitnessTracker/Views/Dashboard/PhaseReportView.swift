import Charts
import SwiftUI

/// An honest, numbers-first read on the current phase: progress against the plan, where it's
/// heading, what off-plan days have cost, how lifts are holding up, and activity by week.
struct PhaseReportView: View {
    @StateObject private var viewModel = PhaseReportViewModel()

    var body: some View {
        List {
            if let report = viewModel.report {
                headerSection(report)
                progressSection(report.progress)
                projectionSection(report)
                if let offPlan = report.offPlan { offPlanSection(offPlan) }
                if let lifts = report.lifts { liftsSection(lifts) }
                weeksSection(report)
                if !report.bottomLine.isEmpty { bottomLineSection(report.bottomLine) }
            } else if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Building the report...").foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            } else if let message = viewModel.message {
                Text(message).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
        }
        .appScreen()
        .navigationTitle("Phase Report")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    // MARK: Formatting

    private func kg(_ value: Double?) -> String { value.map { String(format: "%.1f kg", $0) } ?? "-" }

    /// "-1.5 kg" with a real minus sign.
    private func signedKg(_ value: Double) -> String {
        let text = String(format: "%.1f", abs(value))
        return (value < 0 ? "\u{2212}" : "+") + text + " kg"
    }

    private func shortDate(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }

    // MARK: Sections

    private func headerSection(_ report: PhaseReport) -> some View {
        let header = report.header
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(header.phaseType.displayName) \u{00b7} Week \(header.weekNumber) of \(header.totalWeeks)")
                    .font(.title3.bold())
                Text("\(header.daysLeft) day\(header.daysLeft == 1 ? "" : "s") left \u{00b7} ends \(shortDate(header.endDate))")
                    .foregroundStyle(.secondary)
                Text(([
                    "\(Int(header.calorieTarget.rounded()).formatted()) kcal",
                    "\(Int(header.proteinTarget.rounded())) g protein",
                    header.stepTarget.map { "\($0.formatted()) steps" },
                ] as [String?]).compactMap { $0 }.joined(separator: " \u{00b7} "))
                    .font(.subheadline)
            }
        }
        .listRowBackground(AppRowBackground())
    }

    private func progressSection(_ progress: PhaseReport.Progress) -> some View {
        Section("Progress") {
            if let change = progress.changeKg, let planned = progress.plannedToDateKg {
                let percent = progress.percentOfPlan.map { " (\(Int($0.rounded()))% of plan)" } ?? ""
                Text("\(signedKg(change)) vs \(signedKg(planned)) planned\(percent)")
                    .font(.headline)
            }
            LabeledContent("Start", value: kg(progress.startKg))
            LabeledContent("Now (trend)", value: kg(progress.trendKg))
            if let raw = progress.latestRawKg {
                LabeledContent("Latest weigh-in") { Text(kg(raw)).font(.caption).foregroundStyle(.secondary) }
            }
            if let actual = progress.actualRatePerWeek {
                LabeledContent("Rate", value: "\(signedKg(actual))/week")
            }
            if let planned = progress.plannedRatePerWeek {
                LabeledContent("Planned", value: "\(signedKg(planned))/week")
            }
            if progress.dots.count >= 2 {
                chart(progress)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
        }
        .listRowBackground(AppRowBackground())
    }

    /// Raw weigh-ins as dots (hollow when sick), the trend as a line, the plan as a dashed line.
    private func chart(_ progress: PhaseReport.Progress) -> some View {
        Chart {
            ForEach(progress.dots.filter { !$0.isSick }) { dot in
                PointMark(x: .value("Date", dot.date), y: .value("Weight", dot.kg))
                    .symbolSize(24)
                    .foregroundStyle(.secondary)
            }
            // A sick day is shown as a ring: there, but kept out of the rate.
            ForEach(progress.dots.filter(\.isSick)) { dot in
                PointMark(x: .value("Date", dot.date), y: .value("Weight", dot.kg))
                    .symbol(.circle.strokeBorder(lineWidth: 1.5))
                    .symbolSize(34)
                    .foregroundStyle(.secondary)
            }
            ForEach(progress.trend) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", point.weightKg), series: .value("Line", "Trend"))
                    .foregroundStyle(AppColor.accent)
            }
            ForEach(Array(progress.plannedLine.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", point.kg), series: .value("Line", "Plan"))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 180)
    }

    private func projectionSection(_ report: PhaseReport) -> some View {
        Section("Projection to phase end") {
            if let projection = report.projection {
                Text("Projected end weight on \(shortDate(projection.date)): \(String(format: "%.1f", projection.lowKg))\u{2013}\(String(format: "%.1f", projection.highKg)) kg")
                    .font(.headline)
                Text("At your recent pace, to if fully on plan (with planned treats)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not enough data yet").foregroundStyle(.secondary)
            }
        }
        .listRowBackground(AppRowBackground())
    }

    private func offPlanSection(_ offPlan: PhaseReport.OffPlan) -> some View {
        Section("Off-plan cost") {
            HStack {
                countCell("On plan", offPlan.onPlanDays)
                countCell("Off plan", offPlan.offPlanDays)
                countCell("Sick", offPlan.sickDays)
                countCell("Not tracked", offPlan.notTrackedDays)
            }
            if offPlan.offPlanDays > 0 {
                if let cancelled = offPlan.daysOfDeficitCancelled {
                    Text("Off-plan days cancelled about \(Int(cancelled.rounded())) days of deficit.")
                        .font(.headline)
                }
                LabeledContent("Logged surplus", value: "\(Int(offPlan.loggedSurplusKcal.rounded()).formatted()) kcal")
                if offPlan.offPlanDaysWithoutCalories > 0 {
                    Text("+ \(offPlan.offPlanDaysWithoutCalories) off-plan day\(offPlan.offPlanDaysWithoutCalories == 1 ? "" : "s") with no calories logged, so the real cost is higher.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if offPlan.runCount > 0 {
                    Text("\(offPlan.runCount) of your off-plan stretches ran over several days (longest: \(offPlan.longestRun) days).")
                        .font(.subheadline)
                }
            }
            if let average = offPlan.onPlanAverageKcal, let target = offPlan.onPlanAverageTargetKcal {
                LabeledContent("On-plan average", value: "\(Int(average.rounded()).formatted()) vs \(Int(target.rounded()).formatted()) kcal")
            }
        }
        .listRowBackground(AppRowBackground())
    }

    private func countCell(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func liftsSection(_ lifts: PhaseReport.Lifts) -> some View {
        Section("Lifts on the cut") {
            Text("\(lifts.exercisesUp) of \(lifts.exercisesCounted) exercises up")
                .font(.headline)
            ForEach(lifts.topUp) { liftRow($0) }
            ForEach(lifts.topDown) { liftRow($0) }
        }
        .listRowBackground(AppRowBackground())
    }

    private func liftRow(_ lift: PhaseReport.LiftChange) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lift.name)
                Text(lift.afterBreak ? "\(lift.lastTopSet) \u{00b7} after a break" : lift.lastTopSet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%+.0f%%", lift.percentChange))
                .foregroundStyle(lift.percentChange >= 0 ? AppColor.success : .secondary)
                .monospacedDigit()
        }
    }

    private func weeksSection(_ report: PhaseReport) -> some View {
        Section("Activity by week") {
            ForEach(report.weeks) { week in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Week of \(shortDate(week.monday))\(week.isCurrent ? " (so far)" : "")")
                        .font(.subheadline.weight(.semibold))
                    HStack(alignment: .top) {
                        weekCell("Steps", week.averageSteps.map { $0.formatted() } ?? "-", week.stepsHit)
                        weekCell("Lifts", "\(week.lifts)\(week.liftsTarget.map { "/\($0)" } ?? "")", week.liftsHit)
                        weekCell("Cardio", "\(week.cardioSessions)\(week.cardioSessionsTarget.map { "/\($0)" } ?? "")", week.cardioSessionsHit)
                        weekCell("Cardio min", "\(week.cardioMinutes)", week.cardioMinutesHit)
                        weekCell("Runs", "\(week.runs)\(week.plannedRuns.map { "/\($0)" } ?? "")", week.runsHit)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listRowBackground(AppRowBackground())
    }

    /// Green when the target was hit, plain when missed - never red, so the screen stays readable.
    private func weekCell(_ label: String, _ value: String, _ hit: Bool?) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(hit == true ? AppColor.success : .primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func bottomLineSection(_ lines: [String]) -> some View {
        Section("Bottom line") {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .listRowBackground(AppRowBackground())
    }
}
