import Foundation

/// Plain data in, a `PhaseReport` out - no Supabase, no HealthKit - so every number on the
/// Phase Report can be tested. See `docs`' phase report plan for what each section means.
struct PhaseReportInput {
    struct Session { let id: UUID; let date: Date }
    struct SetRecord {
        let workoutId: UUID
        let exerciseId: UUID
        let reps: Int
        let weightKg: Double
        let isWarmup: Bool
    }

    /// The goal rows that make up this phase (they share a `phaseStartedAt`; the calorie target can change mid-phase).
    var goals: [UserGoal]
    var asOf: Date = Date()
    /// All weigh-ins, including ones before the phase, so the trend line is warmed up when it starts.
    var weights: [BodyWeightLog] = []
    /// ISO date -> calories eaten, from whatever source the app is set to read.
    var dailyCalories: [String: Double] = [:]
    var checkins: [DailyCheckin] = []
    var dayFlags: [DayFlag] = []
    var plannedTreats: [PlannedTreat] = []
    var workouts: [Session] = []
    var sets: [SetRecord] = []
    var exerciseNames: [UUID: String] = [:]
    /// ISO date -> steps.
    var steps: [String: Int] = [:]
    var cardio: [CardioTrackingSession] = []
    var plannedRuns: [PlannedRun] = []
}

struct PhaseReport {
    struct Header {
        let phaseType: GoalPhaseType
        let weekNumber: Int
        let totalWeeks: Int
        let daysLeft: Int
        let endDate: Date
        let calorieTarget: Double
        let proteinTarget: Double
        let stepTarget: Int?
    }

    struct WeightDot: Identifiable {
        let date: Date
        let kg: Double
        /// A sick day: shown, but kept out of the rate.
        let isSick: Bool
        var id: Date { date }
    }

    struct Progress {
        let startKg: Double?
        let trendKg: Double?
        let latestRawKg: Double?
        let changeKg: Double?
        /// Least-squares slope of the trend over the phase.
        let actualRatePerWeek: Double?
        let plannedRatePerWeek: Double?
        let plannedToDateKg: Double?
        /// How much of the planned change has happened so far.
        let percentOfPlan: Double?
        let dots: [WeightDot]
        let trend: [TrendWeightPoint]
        /// Start and end of the planned trajectory, for a dashed line.
        let plannedLine: [(date: Date, kg: Double)]
    }

    struct Projection {
        let lowKg: Double
        let highKg: Double
        let date: Date
    }

    struct OffPlan {
        let onPlanDays: Int
        let offPlanDays: Int
        let sickDays: Int
        let notTrackedDays: Int
        /// Calories over the day's target, summed over off-plan days that have calories.
        let loggedSurplusKcal: Double
        /// That surplus as days of the planned deficit it undid.
        let daysOfDeficitCancelled: Double?
        let offPlanDaysWithoutCalories: Int
        /// Stretches of 2+ off-plan days in a row.
        let runCount: Int
        let longestRun: Int
        let onPlanAverageKcal: Double?
        let onPlanAverageTargetKcal: Double?
    }

    struct LiftChange: Identifiable {
        let exerciseId: UUID
        let name: String
        let firstE1RM: Double
        let recentE1RM: Double
        let peakE1RM: Double
        let percentChange: Double
        let lastTopSet: String
        let afterBreak: Bool
        var id: UUID { exerciseId }
    }

    struct Lifts {
        let exercisesCounted: Int
        let exercisesUp: Int
        let topUp: [LiftChange]
        let topDown: [LiftChange]
    }

    struct WeekRow: Identifiable {
        let monday: Date
        let isCurrent: Bool
        let averageSteps: Int?
        let stepsHit: Bool?
        let lifts: Int
        let liftsTarget: Int?
        let liftsHit: Bool?
        let cardioSessions: Int
        let cardioSessionsTarget: Int?
        let cardioSessionsHit: Bool?
        let cardioMinutes: Int
        let cardioMinutesTarget: Int?
        let cardioMinutesHit: Bool?
        let runs: Int
        let plannedRuns: Int?
        let runsHit: Bool?
        var id: Date { monday }
    }

    let header: Header
    let progress: Progress
    /// nil: not enough data yet.
    let projection: Projection?
    /// nil outside a cut.
    let offPlan: OffPlan?
    let lifts: Lifts?
    let weeks: [WeekRow]
    let bottomLine: [String]
}

struct PhaseReportCalculator {
    /// Kcal per kg of body weight - the same constant the TDEE engine uses.
    static let kcalPerKg = AdaptiveTDEEEngine.kcalPerKg
    static let minWeighInDaysForProjection = 14
    static let minDaysLeftForProjection = 7
    static let minSessionsForALift = 3
    static let breakGapDays = 10

    let input: PhaseReportInput
    private let calendar = Calendar.current

    init(_ input: PhaseReportInput) { self.input = input }

    // MARK: Phase basics

    private var sortedGoals: [UserGoal] { input.goals.sorted { $0.effectiveFrom < $1.effectiveFrom } }
    private var latestGoal: UserGoal? { sortedGoals.last }
    private var firstGoal: UserGoal? { sortedGoals.first }

    private var phaseStart: Date? { firstGoal.flatMap { DateFormatting.date(fromISODate: $0.phaseStartedAt) } }
    private var today: Date { calendar.startOfDay(for: input.asOf) }

    private func iso(_ date: Date) -> String { DateFormatting.isoDate(date) }

    /// The goal in force on a day: the latest row that had started by then.
    func goal(on isoDate: String) -> UserGoal? {
        sortedGoals.last { $0.effectiveFrom <= isoDate } ?? sortedGoals.first
    }

    private func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    private var sickDays: Set<String> { Set(input.dayFlags.filter { $0.status == .sick }.map(\.date)) }
    private var notTrackedFlagDays: Set<String> { Set(input.dayFlags.filter { $0.status == .notTracked }.map(\.date)) }

    // MARK: Build

    func report() -> PhaseReport? {
        guard let goal = latestGoal, let start = phaseStart, let first = firstGoal else { return nil }
        let daysElapsed = max(days(from: start, to: today), 0)
        let totalWeeks = first.durationWeeks
        let end = calendar.date(byAdding: .day, value: totalWeeks * 7, to: start) ?? start
        let header = PhaseReport.Header(
            phaseType: goal.phaseType,
            weekNumber: daysElapsed / 7 + 1,
            totalWeeks: totalWeeks,
            daysLeft: max(days(from: today, to: end), 0),
            endDate: end,
            calorieTarget: goal.dailyCalorieTarget,
            proteinTarget: goal.proteinGTarget,
            stepTarget: goal.stepTarget
        )
        let progress = makeProgress(start: start, daysElapsed: daysElapsed, totalWeeks: totalWeeks, goal: goal, first: first)
        let projection = makeProjection(progress: progress, header: header, end: end, goal: goal)
        let offPlan = goal.phaseType == .cut ? makeOffPlan(start: start, goal: goal) : nil
        let lifts = makeLifts(start: start)
        let weeks = makeWeeks(start: start, goal: goal)
        let bottomLine = makeBottomLine(progress: progress, offPlan: offPlan, lifts: lifts, weeks: weeks, goal: goal)
        return PhaseReport(header: header, progress: progress, projection: projection, offPlan: offPlan,
                           lifts: lifts, weeks: weeks, bottomLine: bottomLine)
    }

    // MARK: Progress

    private func makeProgress(start: Date, daysElapsed: Int, totalWeeks: Int, goal: UserGoal, first: UserGoal) -> PhaseReport.Progress {
        let sick = sickDays
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let inPhase = input.weights.filter { $0.loggedAt >= start && $0.loggedAt < tomorrow }.sorted { $0.loggedAt < $1.loggedAt }
        let dots = inPhase.map { PhaseReport.WeightDot(date: $0.loggedAt, kg: $0.weightKg, isSick: sick.contains(iso($0.loggedAt))) }

        // Start: the first week's average, else what the goal recorded.
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let firstWeek = inPhase.filter { $0.loggedAt < weekEnd && !sick.contains(iso($0.loggedAt)) }.map(\.weightKg)
        let startKg = firstWeek.isEmpty ? first.startingWeightKg : firstWeek.reduce(0, +) / Double(firstWeek.count)

        // Trend over everything (so it's warm at the start), without sick-day dips.
        let trendAll = TrendWeightCalculator.compute(from: input.weights.filter { !sick.contains(iso($0.loggedAt)) })
        let trend = trendAll.filter { $0.date >= start && $0.date < tomorrow }
        let trendKg = trendAll.last { $0.date < tomorrow }?.weightKg
        let latestRaw = inPhase.last?.weightKg

        var rate: Double?
        if trend.count >= 2 {
            let xs = trend.map { Double(days(from: start, to: $0.date)) }
            let ys = trend.map(\.weightKg)
            let meanX = xs.reduce(0, +) / Double(xs.count)
            let meanY = ys.reduce(0, +) / Double(ys.count)
            let denominator = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
            if denominator > 0 {
                let slopePerDay = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / denominator
                rate = slopePerDay * 7
            }
        }

        let planned = goal.weeklyWeightChangeKg
        let weeksElapsed = Double(daysElapsed) / 7
        let plannedToDate = planned.map { $0 * weeksElapsed }
        let change = (trendKg != nil && startKg != nil) ? trendKg! - startKg! : nil
        var percent: Double?
        if let change, let plannedToDate, abs(plannedToDate) > 0.0001 { percent = change / plannedToDate * 100 }

        var plannedLine: [(date: Date, kg: Double)] = []
        if let startKg, let planned {
            let end = calendar.date(byAdding: .day, value: totalWeeks * 7, to: start) ?? start
            plannedLine = [(start, startKg), (end, startKg + planned * Double(totalWeeks))]
        }
        return PhaseReport.Progress(
            startKg: startKg, trendKg: trendKg, latestRawKg: latestRaw, changeKg: change,
            actualRatePerWeek: rate, plannedRatePerWeek: planned, plannedToDateKg: plannedToDate,
            percentOfPlan: percent, dots: dots, trend: trend, plannedLine: plannedLine
        )
    }

    // MARK: Projection

    private func makeProjection(progress: PhaseReport.Progress, header: PhaseReport.Header, end: Date, goal: UserGoal) -> PhaseReport.Projection? {
        guard let start = phaseStart else { return nil }
        let weighInDays = Set(input.weights.filter { $0.loggedAt >= start }.map { iso($0.loggedAt) })
        guard weighInDays.count >= Self.minWeighInDaysForProjection, header.daysLeft >= Self.minDaysLeftForProjection,
              let trend = progress.trendKg, let actual = progress.actualRatePerWeek,
              let planned = progress.plannedRatePerWeek else { return nil }
        let weeksLeft = Double(header.daysLeft) / 7
        let recentPace = trend + actual * weeksLeft
        let treatKcal = input.plannedTreats.reduce(0.0) { total, treat in
            guard let date = DateFormatting.date(fromISODate: treat.date), date > today, date <= end else { return total }
            return total + treat.extraCalories
        }
        let onPlan = trend + planned * weeksLeft + treatKcal / Self.kcalPerKg
        return PhaseReport.Projection(lowKg: min(recentPace, onPlan), highKg: max(recentPace, onPlan), date: end)
    }

    // MARK: Off-plan cost

    private func makeOffPlan(start: Date, goal: UserGoal) -> PhaseReport.OffPlan {
        let offPlanSet = OffPlanDays.days(from: input.checkins)
        let sick = sickDays
        let checkinDates = Set(input.checkins.map(\.checkinDate))
        let planned = goal.weeklyWeightChangeKg.map { abs($0) * Self.kcalPerKg / 7 }

        var onPlan = 0, offPlan = 0, sickCount = 0, notTracked = 0
        var surplus = 0.0
        var offPlanNoCalories = 0
        var offPlanDates: [Date] = []
        var onPlanCalories: [Double] = []
        var onPlanTargets: [Double] = []

        var day = start
        while day < today {
            let key = iso(day)
            let calories = input.dailyCalories[key]
            let target = self.goal(on: key)?.dailyCalorieTarget
            if sick.contains(key) {
                sickCount += 1
            } else if offPlanSet.contains(key) {
                offPlan += 1
                offPlanDates.append(day)
                if let calories, let target { surplus += calories - target } else { offPlanNoCalories += 1 }
            } else if notTrackedFlagDays.contains(key) || (calories == nil && !checkinDates.contains(key)) {
                notTracked += 1
            } else {
                onPlan += 1
                if let calories, let target { onPlanCalories.append(calories); onPlanTargets.append(target) }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today
        }

        // Runs of consecutive off-plan days.
        var runs: [Int] = []
        var length = 0
        var previous: Date?
        for date in offPlanDates.sorted() {
            if let previous, days(from: previous, to: date) == 1 { length += 1 } else {
                if length >= 2 { runs.append(length) }
                length = 1
            }
            previous = date
        }
        if length >= 2 { runs.append(length) }

        let cancelled = planned.flatMap { $0 > 0 ? max(surplus, 0) / $0 : nil }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        return PhaseReport.OffPlan(
            onPlanDays: onPlan, offPlanDays: offPlan, sickDays: sickCount, notTrackedDays: notTracked,
            loggedSurplusKcal: surplus, daysOfDeficitCancelled: cancelled,
            offPlanDaysWithoutCalories: offPlanNoCalories, runCount: runs.count, longestRun: runs.max() ?? 0,
            onPlanAverageKcal: mean(onPlanCalories), onPlanAverageTargetKcal: mean(onPlanTargets)
        )
    }

    // MARK: Lifts

    private func makeLifts(start: Date) -> PhaseReport.Lifts? {
        let phaseWorkouts = input.workouts.filter { $0.date >= start }
        let dateById = Dictionary(phaseWorkouts.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first })
        // Best estimated one-rep max per exercise per session, from working sets only.
        struct Best { var e1rm: Double; var set: String }
        var perSession: [UUID: [UUID: Best]] = [:]   // exercise -> workout -> best
        for set in input.sets where !set.isWarmup && (1...15).contains(set.reps) && set.weightKg > 0 && dateById[set.workoutId] != nil {
            let e1rm = set.weightKg * (1 + Double(set.reps) / 30)
            let label = "\(AmountLabel.trimmed(set.weightKg)) \u{00d7} \(set.reps)"
            if let existing = perSession[set.exerciseId]?[set.workoutId], existing.e1rm >= e1rm { continue }
            perSession[set.exerciseId, default: [:]][set.workoutId] = Best(e1rm: e1rm, set: label)
        }

        let sick = sickDays
        var changes: [PhaseReport.LiftChange] = []
        for (exerciseId, sessions) in perSession where sessions.count >= Self.minSessionsForALift {
            let ordered = sessions.compactMap { id, best in dateById[id].map { (date: $0, best: best) } }.sorted { $0.date < $1.date }
            guard let first = ordered.first, ordered.count >= 2 else { continue }
            let lastTwo = ordered.suffix(2)
            let recent = lastTwo.map(\.best.e1rm).reduce(0, +) / Double(lastTwo.count)
            let peak = ordered.map(\.best.e1rm).max() ?? first.best.e1rm
            let percent = (recent - first.best.e1rm) / first.best.e1rm * 100
            // A drop after a gap of more than 10 days, or an illness in it, isn't a real loss of strength.
            let gapStart = lastTwo.first!.date, gapEnd = lastTwo.last!.date
            let gapDays = days(from: gapStart, to: gapEnd)
            var sickInGap = false
            var cursor = calendar.date(byAdding: .day, value: 1, to: gapStart) ?? gapStart
            while cursor < gapEnd { if sick.contains(iso(cursor)) { sickInGap = true; break }; cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gapEnd }
            changes.append(PhaseReport.LiftChange(
                exerciseId: exerciseId, name: input.exerciseNames[exerciseId] ?? "Exercise",
                firstE1RM: first.best.e1rm, recentE1RM: recent, peakE1RM: peak, percentChange: percent,
                lastTopSet: ordered.last?.best.set ?? "", afterBreak: gapDays > Self.breakGapDays || sickInGap
            ))
        }
        guard !changes.isEmpty else { return nil }
        let up = changes.filter { $0.percentChange > 0 }
        return PhaseReport.Lifts(
            exercisesCounted: changes.count, exercisesUp: up.count,
            topUp: Array(up.sorted { $0.percentChange > $1.percentChange }.prefix(3)),
            topDown: Array(changes.filter { $0.percentChange < 0 }.sorted { $0.percentChange < $1.percentChange }.prefix(3))
        )
    }

    // MARK: Activity by week

    private func makeWeeks(start: Date, goal: UserGoal) -> [PhaseReport.WeekRow] {
        let firstMonday = DateFormatting.mondayOfWeek(containing: start)
        let currentMonday = DateFormatting.mondayOfWeek(containing: today)
        var rows: [PhaseReport.WeekRow] = []
        var monday = firstMonday
        while monday <= currentMonday {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
            let inWeek: (Date) -> Bool = { $0 >= monday && $0 < weekEnd }

            let stepDays = input.steps.compactMap { key, value -> Int? in
                guard let date = DateFormatting.date(fromISODate: key), inWeek(date) else { return nil }
                return value
            }
            let average = stepDays.isEmpty ? nil : stepDays.reduce(0, +) / stepDays.count
            let lifts = input.workouts.filter { inWeek($0.date) }.count
            let required = goal.strengthSessionsPerWeek.map { max($0 - (goal.strengthOptionalSessions ?? 0), 0) }
            let cardio = input.cardio.filter { inWeek($0.startedAt) && $0.cardioType != .outdoorRun }
            let minutes = Int((cardio.reduce(0.0) { $0 + $1.elapsed() } / 60).rounded())
            let sessionsTarget = goal.cardioSessionsPerWeek
            let minutesTarget = sessionsTarget.flatMap { sessions in goal.cardioMinutesPerSession.map { sessions * $0 } }
            let runs = input.cardio.filter { inWeek($0.startedAt) && $0.cardioType == .outdoorRun }.count
            let planned = input.plannedRuns.filter { $0.runType != .rest && inWeek($0.day) }.count
            let plannedTarget: Int? = input.plannedRuns.isEmpty ? nil : planned

            rows.append(PhaseReport.WeekRow(
                monday: monday, isCurrent: monday == currentMonday,
                averageSteps: average, stepsHit: average.flatMap { avg in goal.stepTarget.map { avg >= $0 } },
                lifts: lifts, liftsTarget: required, liftsHit: required.map { lifts >= $0 },
                cardioSessions: cardio.count, cardioSessionsTarget: sessionsTarget, cardioSessionsHit: sessionsTarget.map { cardio.count >= $0 },
                cardioMinutes: minutes, cardioMinutesTarget: minutesTarget, cardioMinutesHit: minutesTarget.map { minutes >= $0 },
                runs: runs, plannedRuns: plannedTarget, runsHit: plannedTarget.map { runs >= $0 }
            ))
            monday = weekEnd
        }
        return rows.reversed()
    }

    // MARK: Bottom line

    private func makeBottomLine(progress: PhaseReport.Progress, offPlan: PhaseReport.OffPlan?, lifts: PhaseReport.Lifts?,
                                weeks: [PhaseReport.WeekRow], goal: UserGoal) -> [String] {
        var lines: [String] = []
        if let actual = progress.actualRatePerWeek, let planned = progress.plannedRatePerWeek, abs(planned) > 0.0001 {
            let fraction = actual / planned
            if fraction >= 0.8 {
                lines.append("On track.")
            } else if let offPlan, let toDate = progress.plannedToDateKg, let change = progress.changeKg {
                let missingKcal = abs(toDate - change) * Self.kcalPerKg
                if missingKcal > 0, offPlan.loggedSurplusKcal >= 0.7 * missingKcal {
                    var text = "Your on-plan days are working. Off-plan days explain most of the gap."
                    if offPlan.runCount >= 2 { text += " Watch the day after an off-plan day." }
                    lines.append(text)
                } else {
                    lines.append("On-plan days aren't producing the planned rate. Review intake accuracy or the target.")
                }
            } else {
                lines.append("Progress is behind the planned rate.")
            }
        }

        // Activity: any column under target in at least two of the last three weeks.
        let recent = Array(weeks.prefix(3))
        let columns: [(String, (PhaseReport.WeekRow) -> Bool?)] = [
            ("Steps", { $0.stepsHit }), ("Lifting sessions", { $0.liftsHit }),
            ("Cardio sessions", { $0.cardioSessionsHit }), ("Cardio minutes", { $0.cardioMinutesHit }),
        ]
        for (name, hit) in columns {
            let judged = recent.compactMap(hit)
            if judged.count >= 2, judged.filter({ !$0 }).count >= 2 {
                lines.append("\(name) were below target in \(judged.filter { !$0 }.count) of the last \(judged.count) weeks.")
            }
        }

        if let lifts, lifts.exercisesCounted > 0, Double(lifts.exercisesUp) / Double(lifts.exercisesCounted) >= 0.6 {
            lines.append("Strength is holding: muscle retention looks good.")
        }
        return lines
    }
}
