import Foundation

/// The weekly review of a running plan: how last week actually went (distance, effort, heart
/// rate, pace) against what was planned, as one of three calls - progress, hold or back off -
/// and the change to the coming runs that call suggests. Plain rules over data already
/// recorded; nothing here changes the plan, it only proposes (the owner confirms).
enum RunFeedback {
    enum Call: Equatable { case progress, hold, backOff }

    /// One planned run of the week under review, and what the Watch recorded for it.
    struct Result {
        let runType: RunType
        let targetKm: Double?
        /// nil when the run wasn't done.
        let actualKm: Double?
        /// 1-10, from the Watch's effort rating.
        let effort: Int?
        let avgHeartRate: Int?
        /// Average heart rate of recent runs of the same type, to compare this one against.
        let heartRateBaseline: Double?
        let targetPaceSec: Double?
        let actualPaceSec: Double?
    }

    struct Verdict: Equatable {
        let call: Call
        /// Plain reasons, shown under the suggestion.
        let reasons: [String]
    }

    // Thresholds - starting values, to tune once this has run for a few weeks.
    /// A run counts as hitting its distance at this fraction of the target (GPS is never exact).
    static let hitFraction = 0.97
    /// Below this fraction of the target it counts as short.
    static let shortFraction = 0.90
    /// Heart rate this much above the baseline for that run type is "markedly above".
    static let heartRateAboveBaseline = 1.07
    /// A long run this much slower than its target pace is "significantly slower".
    static let slowPaceFactor = 1.10
    /// An effort rating this high is a hard run.
    static let hardEffort = 8
    /// How much to take off the coming runs when backing off.
    static let backOffPercent = 15.0

    /// The call for a finished week; nil when nothing in it had a distance target to judge.
    static func verdict(for results: [Result]) -> Verdict? {
        let judged = results.filter { ($0.targetKm ?? 0) > 0 }
        guard !judged.isEmpty else { return nil }

        let missedOrShort = judged.filter { run in
            guard let actual = run.actualKm, let target = run.targetKm else { return true }
            return actual < target * shortFraction
        }
        let hitAll = judged.allSatisfy { run in
            guard let actual = run.actualKm, let target = run.targetKm else { return false }
            return actual >= target * hitFraction
        }
        let ratedTen = results.contains { $0.effort == 10 }
        let hardRun = results.contains { ($0.effort ?? 0) >= hardEffort }
        let hardEasy = results.contains { $0.runType == .easy && ($0.effort ?? 0) >= hardEffort }
        let heartRateHigh = results.contains { run in
            guard let heartRate = run.avgHeartRate, let baseline = run.heartRateBaseline else { return false }
            return Double(heartRate) > baseline * heartRateAboveBaseline
        }
        let slowLong = results.first { run in
            guard run.runType == .long, let target = run.targetPaceSec, let actual = run.actualPaceSec else { return false }
            return actual > target * slowPaceFactor
        }

        var backOffReasons: [String] = []
        if missedOrShort.count >= 2 { backOffReasons.append("\(missedOrShort.count) runs were missed or short") }
        if ratedTen { backOffReasons.append("A run was rated 10 for effort") }
        if let slowLong, let target = slowLong.targetPaceSec, let actual = slowLong.actualPaceSec {
            backOffReasons.append("The long run was \(Int(((actual / target) - 1) * 100))% slower than its target pace")
        }
        if !backOffReasons.isEmpty { return Verdict(call: .backOff, reasons: backOffReasons) }

        if hitAll && !hardEasy && !heartRateHigh {
            return Verdict(call: .progress, reasons: ["Every run hit its distance", "No easy run felt hard", "Heart rate was in its usual range"])
        }

        var holdReasons: [String] = []
        if missedOrShort.count == 1 { holdReasons.append("One run was missed or short") }
        if hardRun { holdReasons.append("A run was rated \(results.compactMap(\.effort).max() ?? hardEffort) for effort") }
        if heartRateHigh { holdReasons.append("Heart rate was higher than usual on a run") }
        if holdReasons.isEmpty { holdReasons.append("Not enough to say it was a clear step up") }
        return Verdict(call: .hold, reasons: holdReasons)
    }

    struct Change: Equatable {
        let runId: UUID
        let fromKm: Double
        let toKm: Double
    }

    struct Suggestion: Equatable {
        let call: Call
        let weekNumber: Int
        let title: String
        let detail: String
        let reasons: [String]
        /// Empty when the suggestion is just a go-ahead - there is nothing to apply.
        let changes: [Change]
    }

    /// What the call means for the runs still to do in the coming week. `thisWeek` is the week
    /// that was reviewed (with its planned targets), `upcoming` the runs still ahead. Nil when
    /// the plan already says what the call would suggest.
    static func suggestion(for verdict: Verdict, thisWeek: [PlannedRun], upcoming: [PlannedRun], weekNumber: Int) -> Suggestion? {
        let longRun: ([PlannedRun]) -> PlannedRun? = { runs in
            runs.filter { $0.runType == .long && ($0.targetDistanceKm ?? 0) > 0 }.max { ($0.targetDistanceKm ?? 0) < ($1.targetDistanceKm ?? 0) }
        }
        let weekday: (PlannedRun) -> String = { $0.day.formatted(.dateTime.weekday(.wide)) }

        switch verdict.call {
        case .progress:
            // The plan's own progression stands: confirm it's warranted, don't add to it.
            guard let reviewed = longRun(thisWeek)?.targetDistanceKm, let next = longRun(upcoming),
                  let nextKm = next.targetDistanceKm, nextKm > reviewed else { return nil }
            return Suggestion(call: .progress, weekNumber: weekNumber, title: "Last week looked strong",
                              detail: "Go ahead with \(weekday(next))'s \(RunFormat.km(nextKm)) long run as planned.",
                              reasons: verdict.reasons, changes: [])
        case .hold:
            guard let reviewed = longRun(thisWeek)?.targetDistanceKm, let next = longRun(upcoming),
                  let nextKm = next.targetDistanceKm, nextKm > reviewed else { return nil }
            return Suggestion(call: .hold, weekNumber: weekNumber, title: "Hold the long run",
                              detail: "Repeat \(RunFormat.km(reviewed)) on \(weekday(next)) instead of stepping up to \(RunFormat.km(nextKm)).",
                              reasons: verdict.reasons,
                              changes: [Change(runId: next.id, fromKm: nextKm, toKm: reviewed)])
        case .backOff:
            let changes: [Change] = upcoming.compactMap { run in
                guard run.runType != .rest, let km = run.targetDistanceKm, km > 0 else { return nil }
                let reduced = (km * (1 - backOffPercent / 100) * 2).rounded() / 2
                // Keep room for the warm-up and cool-down inside the total.
                let floor = (run.warmupKm ?? 0) + (run.cooldownKm ?? 0) + 0.5
                let target = max(reduced, floor, 1)
                return target < km ? Change(runId: run.id, fromKm: km, toKm: target) : nil
            }
            guard !changes.isEmpty else { return nil }
            return Suggestion(call: .backOff, weekNumber: weekNumber, title: "Ease off",
                              detail: "Take about \(Int(backOffPercent))% off the \(changes.count) run\(changes.count == 1 ? "" : "s") still to do this week.",
                              reasons: verdict.reasons, changes: changes)
        }
    }
}
