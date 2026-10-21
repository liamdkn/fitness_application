import Foundation

// Pure maths for the Coach (see docs/coach-plan.md): plain data in, value types out. No
// Supabase, no HealthKit, no UI - so every number the coach quotes can be tested.
//
// Sleep and steps are deliberately NOT modelled. Across 17 Aug - 20 Oct neither predicted an
// off-plan day (under 7 h sleep: 47% off vs 50%; steps 11,004 on-plan vs 10,342 off-plan).
// Don't add them back as conditions without fresh evidence.

/// How a finished day went. Anything that isn't perfect is off plan.
enum CoachDayStatus: String {
    /// Fully logged, not flagged off-plan, within target.
    case on
    /// The next morning's check-in said it was off plan.
    case flagged
    /// Under 80% of the calorie target logged.
    case blank
    /// Logged more than target + 150 + any planned treat.
    case over

    var isOn: Bool { self == .on }

    var displayName: String {
        switch self {
        case .on: "On plan"
        case .flagged: "Off plan"
        case .blank: "Barely logged"
        case .over: "Over target"
        }
    }
}

struct CoachDayRecord: Identifiable, Equatable {
    /// ISO date (yyyy-MM-dd).
    let date: String
    /// Calendar weekday: 1 = Sunday ... 7 = Saturday.
    let weekday: Int
    let status: CoachDayStatus
    /// Sick days count as off plan in the totals but are left out of pattern learning.
    let isSick: Bool
    let trained: Bool
    let scheduledTraining: Bool
    let isTreatDay: Bool
    /// Hunger the check-in on the next morning recorded for this day (1-5).
    let hunger: Int?
    let calories: Double
    let proteinG: Double?
    let target: Double
    /// What the next morning's check-in said about why the day was off plan.
    let note: String?

    var id: String { date }
}

enum WeaknessKind: Hashable {
    case afterSlip
    case noTraining
    case weekday(Int)
    case lowLogging
    case highHunger
}

/// How often one kind of day went off plan, against all the other days.
struct ConditionStat: Identifiable {
    let kind: WeaknessKind
    let label: String
    let off: Int
    let n: Int
    /// The same count for the days that don't meet the condition.
    let restOff: Int
    let restN: Int

    var id: String { label }
    var offRate: Double { n == 0 ? 0 : Double(off) / Double(n) }
    var restRate: Double { restN == 0 ? 0 : Double(restOff) / Double(restN) }
}

struct Weakness: Identifiable {
    let kind: WeaknessKind
    let label: String
    let offRate: Double
    /// Off-plan rate over every day that counts for learning.
    let baselineOffRate: Double
    /// Off-plan rate on the days that don't meet the condition.
    let restOffRate: Double
    let off: Int
    let n: Int

    var id: String { label }
    /// Bigger gap and bigger sample first.
    var score: Double { (offRate - restOffRate) * Double(n).squareRoot() }
}

struct CoachStreak: Equatable {
    let onPlan: Bool
    let length: Int
}

struct CoachOffRun: Identifiable, Equatable {
    let start: String
    let length: Int
    var id: String { start }
}

struct CoachStatusCounts: Equatable {
    var on = 0
    var flagged = 0
    var blank = 0
    var over = 0

    var total: Int { on + flagged + blank + over }
    var off: Int { flagged + blank + over }
    var onShare: Double { total == 0 ? 0 : Double(on) / Double(total) }
}

struct CoachSnapshot {
    /// Every finished day of the phase, oldest first.
    let days: [CoachDayRecord]
    /// Off-plan rate over the days that count for learning (sick days left out).
    let baseline: Double
    let weaknesses: [Weakness]
    /// Every condition's numbers, weak or not - the weak-spots chart draws from these.
    let conditions: [ConditionStat]
    /// The streak the most recent finished day belongs to.
    let currentRun: CoachStreak?
    let longestOffRun: Int
    /// Off-plan stretches in order. Sick days count as off here.
    let offRuns: [CoachOffRun]
    let counts: CoachStatusCounts

    var onPlanStreak: Int {
        guard let currentRun, currentRun.onPlan else { return 0 }
        return currentRun.length
    }

    func weakness(_ kind: WeaknessKind) -> Weakness? { weaknesses.first { $0.kind == kind } }
    func condition(_ kind: WeaknessKind) -> ConditionStat? { conditions.first { $0.kind == kind } }
}

struct CoachInput {
    /// The goal rows of the phase (a mid-phase target change adds a row with the same start).
    var goals: [UserGoal]
    var now: Date = Date()
    /// ISO date -> calories eaten, from whatever source the app is set to read.
    var dailyCalories: [String: Double] = [:]
    var dailyProtein: [String: Double] = [:]
    var checkins: [DailyCheckin] = []
    var dayFlags: [DayFlag] = []
    var plannedTreats: [PlannedTreat] = []
    /// ISO dates with at least one workout. One entry per date, so duplicate rows (HealthKit plus
    /// manual) don't matter.
    var workoutDates: Set<String> = []
    /// When recent workouts started, to learn the usual gym time for each weekday.
    var workoutStarts: [Date] = []
    /// Weekday (1 = Sunday) to what the split holds.
    var plan: [Int: TrainingDayService.DayPlan] = [:]
}

/// The one message the dashboard card shows.
struct CoachMessage: Equatable {
    enum Kind: Equatable { case roughStretch, afterSlip, lowLogging, noTraining, weekday, treatDay, sick, normal }
    enum Action: Equatable {
        case startWorkout
        case openNutrition(daysFromToday: Int)
        case logTreat
    }

    let kind: Kind
    let text: String
    let action: Action?
    let actionTitle: String?
}

struct CoachWeekCell: Identifiable {
    let date: Date
    let record: CoachDayRecord?
    let isToday: Bool
    let isFuture: Bool
    /// Inside the phase (a row's first or last days can fall outside it).
    let inPhase: Bool
    var id: Date { date }
}

struct CoachWeek: Identifiable {
    let monday: Date
    let cells: [CoachWeekCell]
    var id: Date { monday }
    var onCount: Int { cells.filter { $0.record?.status.isOn == true }.count }
}

struct CoachEngine {
    static let fullyLoggedShare = 0.8
    static let overTolerance = 150.0
    static let minSampleForWeakness = 8
    static let weaknessMargin = 0.15
    static let highHungerLevel = 4
    static let roughStretchDays = 5
    /// How long after the usual start a missing session becomes worth a word.
    static let lateAfterUsualStartHours = 2.0
    static let fallbackStartHour = 12.0
    /// A day with no check-in the next morning is final from 04:00.
    static let dayClosesAtHour = 4

    let input: CoachInput
    private let calendar = Calendar.current

    init(_ input: CoachInput) { self.input = input }

    // MARK: Basics

    private var sortedGoals: [UserGoal] { input.goals.sorted { $0.effectiveFrom < $1.effectiveFrom } }

    var phaseStart: Date? {
        sortedGoals.first.flatMap { DateFormatting.date(fromISODate: $0.phaseStartedAt) }
    }

    private var today: Date { calendar.startOfDay(for: input.now) }

    private func iso(_ date: Date) -> String { DateFormatting.isoDate(date) }

    private func addDays(_ n: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: n, to: date) ?? date }

    /// The goal in force on a day: the latest row that had started by then.
    func goal(on isoDate: String) -> UserGoal? {
        sortedGoals.last { $0.effectiveFrom <= isoDate } ?? sortedGoals.first
    }

    // MARK: Classification

    func snapshot() -> CoachSnapshot {
        let days = classifiedDays()
        let learning = Self.learn(days)

        var counts = CoachStatusCounts()
        for day in days {
            switch day.status {
            case .on: counts.on += 1
            case .flagged: counts.flagged += 1
            case .blank: counts.blank += 1
            case .over: counts.over += 1
            }
        }

        let runs = Self.offRuns(in: days)
        var streak: CoachStreak?
        if let last = days.last {
            var length = 0
            for day in days.reversed() {
                if day.status.isOn == last.status.isOn { length += 1 } else { break }
            }
            streak = CoachStreak(onPlan: last.status.isOn, length: length)
        }

        return CoachSnapshot(
            days: days,
            baseline: learning.baseline,
            weaknesses: learning.weaknesses,
            conditions: learning.conditions,
            currentRun: streak,
            longestOffRun: runs.map(\.length).max() ?? 0,
            offRuns: runs,
            counts: counts
        )
    }

    /// Every day of the phase that is over, oldest first. Today is never classified: a day is
    /// final once the next morning's check-in is in, or from 04:00 the next morning without one.
    func classifiedDays() -> [CoachDayRecord] {
        guard let start = phaseStart else { return [] }
        let checkinsByDate = Dictionary(input.checkins.map { ($0.checkinDate, $0) }, uniquingKeysWith: { _, latest in latest })
        let sick = Set(input.dayFlags.filter { $0.status == .sick }.map(\.date))
        let treatExtra = Dictionary(grouping: input.plannedTreats, by: \.date).mapValues { $0.reduce(0) { $0 + $1.extraCalories } }

        var records: [CoachDayRecord] = []
        var date = calendar.startOfDay(for: start)
        while date < today {
            defer { date = addDays(1, to: date) }
            let key = iso(date)
            let next = addDays(1, to: date)
            let nextCheckin = checkinsByDate[iso(next)]
            let closesAt = calendar.date(byAdding: .hour, value: Self.dayClosesAtHour, to: next) ?? next
            guard nextCheckin != nil || input.now >= closesAt else { continue }
            guard let goal = goal(on: key) else { continue }

            let calories = input.dailyCalories[key] ?? 0
            let target = goal.dailyCalorieTarget
            let extra = treatExtra[key] ?? 0
            let status: CoachDayStatus
            if nextCheckin?.yesterdayOffPlan == true {
                status = .flagged
            } else if calories < target * Self.fullyLoggedShare {
                status = .blank
            } else if calories > target + Self.overTolerance + extra {
                status = .over
            } else {
                status = .on
            }

            let weekday = calendar.component(.weekday, from: date)
            let note = nextCheckin?.yesterdayOffPlanNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
            records.append(CoachDayRecord(
                date: key,
                weekday: weekday,
                status: status,
                isSick: sick.contains(key),
                trained: input.workoutDates.contains(key),
                scheduledTraining: input.plan[weekday]?.type == .workout,
                isTreatDay: extra > 0 || input.plannedTreats.contains { $0.date == key },
                hunger: nextCheckin?.yesterdayHungerLevel,
                calories: calories,
                proteinG: input.dailyProtein[key],
                target: target,
                note: (note?.isEmpty ?? true) ? nil : note
            ))
        }
        return records
    }

    // MARK: Learning

    struct Learning {
        let baseline: Double
        let conditions: [ConditionStat]
        let weaknesses: [Weakness]
    }

    /// (A barely logged day before is a card rule, not a learned condition: `lowLogging` is only ever
    /// picked from yesterday's status.)
    ///
    /// Off-plan rate of every condition against the days that don't meet it. A condition is a
    /// weakness when it has at least 8 days and runs 15 points above those other days.
    ///
    /// The comparison is against the other days rather than the overall rate: the overall rate
    /// includes the condition's own days, which makes a condition that is most of the problem look
    /// less unusual than it is. (On the 17 Aug - 20 Oct data, untrained days went off 23/34 = 68%
    /// against an overall 54%, just under +15 points, though trained days went off only 39%.)
    static func learn(_ days: [CoachDayRecord]) -> Learning {
        let usable = days.indices.filter { !days[$0].isSick }
        let offTotal = usable.filter { !days[$0].status.isOn }.count
        let baseline = usable.isEmpty ? 0 : Double(offTotal) / Double(usable.count)

        func isOff(_ i: Int) -> Bool { !days[i].status.isOn }

        /// Counts the days in `group` and in `rest`.
        func stat(_ kind: WeaknessKind, _ label: String, group: [Int], rest: [Int]) -> ConditionStat {
            ConditionStat(
                kind: kind, label: label,
                off: group.filter(isOff).count, n: group.count,
                restOff: rest.filter(isOff).count, restN: rest.count
            )
        }

        var conditions: [ConditionStat] = []

        // After a day that wasn't on plan, against after one that was. Days following a sick day
        // aren't a behaviour signal either way.
        let withPrev = usable.filter { $0 > 0 && !days[$0 - 1].isSick }
        conditions.append(stat(
            .afterSlip, "After an off day",
            group: withPrev.filter { !days[$0 - 1].status.isOn },
            rest: withPrev.filter { days[$0 - 1].status.isOn }
        ))
        conditions.append(stat(
            .noTraining, "No session",
            group: usable.filter { !days[$0].trained },
            rest: usable.filter { days[$0].trained }
        ))
        let withHunger = usable.filter { days[$0].hunger != nil }
        conditions.append(stat(
            .highHunger, "Hungry day",
            group: withHunger.filter { (days[$0].hunger ?? 0) >= highHungerLevel },
            rest: withHunger.filter { (days[$0].hunger ?? 0) < highHungerLevel }
        ))
        for weekday in 1...7 {
            conditions.append(stat(
                .weekday(weekday), weekdayName(weekday),
                group: usable.filter { days[$0].weekday == weekday },
                rest: usable.filter { days[$0].weekday != weekday }
            ))
        }

        let weaknesses = conditions
            .filter { $0.n >= minSampleForWeakness && $0.restN > 0 && $0.offRate >= $0.restRate + weaknessMargin }
            .map { Weakness(kind: $0.kind, label: $0.label, offRate: $0.offRate, baselineOffRate: baseline, restOffRate: $0.restRate, off: $0.off, n: $0.n) }
            .sorted { $0.score > $1.score }
        return Learning(baseline: baseline, conditions: conditions, weaknesses: weaknesses)
    }

    /// Stretches of consecutive off-plan days, in order. Sick days count as off here.
    static func offRuns(in days: [CoachDayRecord]) -> [CoachOffRun] {
        var runs: [CoachOffRun] = []
        var start: String?
        var length = 0
        for day in days {
            if day.status.isOn {
                if let start { runs.append(CoachOffRun(start: start, length: length)) }
                start = nil
                length = 0
            } else {
                if start == nil { start = day.date }
                length += 1
            }
        }
        if let start { runs.append(CoachOffRun(start: start, length: length)) }
        return runs
    }

    static func weekdayName(_ weekday: Int) -> String {
        WeeklyScheduleDay.weekdaySymbols[weekday] ?? ""
    }

    // MARK: Calendar

    /// When the phase ends (exclusive): its start plus its length.
    var phaseEnd: Date? {
        guard let start = phaseStart, let weeks = sortedGoals.first?.durationWeeks else { return nil }
        return addDays(weeks * 7, to: calendar.startOfDay(for: start))
    }

    /// Monday-Sunday rows from the phase's first week to the current week, or on to the phase's
    /// last week. Today and days still to come have no record.
    func calendarWeeks(days: [CoachDayRecord], throughPhaseEnd: Bool = false) -> [CoachWeek] {
        guard let start = phaseStart else { return [] }
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var monday = DateFormatting.mondayOfWeek(containing: start)
        var last = today
        if throughPhaseEnd, let end = phaseEnd { last = max(today, addDays(-1, to: end)) }
        let lastMonday = DateFormatting.mondayOfWeek(containing: last)
        let phaseStartDay = calendar.startOfDay(for: start)
        var weeks: [CoachWeek] = []
        while monday <= lastMonday {
            let cells = (0..<7).map { offset -> CoachWeekCell in
                let date = addDays(offset, to: monday)
                let inPhase = date >= phaseStartDay && (phaseEnd.map { date < $0 } ?? true)
                return CoachWeekCell(date: date, record: byDate[iso(date)], isToday: date == today, isFuture: date > today, inPhase: inPhase)
            }
            weeks.append(CoachWeek(monday: monday, cells: cells))
            monday = addDays(7, to: monday)
        }
        return weeks
    }

    /// Today looks on plan so far: enough logged and not over budget. Only provisional - the day
    /// is confirmed by the next morning's check-in.
    func todayProvisionallyOnPlan() -> Bool {
        let key = iso(today)
        if input.dayFlags.contains(where: { $0.date == key && $0.status == .sick }) { return false }
        guard let goal = goal(on: key) else { return false }
        let calories = input.dailyCalories[key] ?? 0
        let extra = input.plannedTreats.filter { $0.date == key }.reduce(0) { $0 + $1.extraCalories }
        return !(calories < goal.dailyCalorieTarget * Self.fullyLoggedShare)
            && !(calories > goal.dailyCalorieTarget + Self.overTolerance + extra)
    }

    /// This week's seven days.
    func thisWeek(days: [CoachDayRecord]) -> CoachWeek? {
        calendarWeeks(days: days).last
    }

    // MARK: Today's message

    /// The usual gym start for a weekday: the median start time (hours, 8.5 = 08:30) of its
    /// sessions over the last four weeks, one per date. Nil without any.
    func usualStartHour(weekday: Int) -> Double? {
        let cutoff = addDays(-28, to: today)
        var earliest: [String: Date] = [:]
        for start in input.workoutStarts where start >= cutoff && calendar.component(.weekday, from: start) == weekday {
            let key = iso(start)
            if let existing = earliest[key], existing <= start { continue }
            earliest[key] = start
        }
        let hours = earliest.values.map { start -> Double in
            Double(calendar.component(.hour, from: start)) + Double(calendar.component(.minute, from: start)) / 60
        }.sorted()
        guard !hours.isEmpty else { return nil }
        let middle = hours.count / 2
        return hours.count % 2 == 1 ? hours[middle] : (hours[middle - 1] + hours[middle]) / 2
    }

    /// One message, by priority: after a slip, a barely logged day, no session yet, a weak
    /// weekday, a planned treat, then the plain status. Never suggests eating less, extra cardio
    /// or skipping meals to make up for an off day - after a slip it is always "back to normal".
    func message(snapshot: CoachSnapshot) -> CoachMessage {
        let weekday = calendar.component(.weekday, from: today)
        let todayKey = iso(today)
        let todayGoal = goal(on: todayKey)
        let plan = input.plan[weekday]
        let isTrainingDay = plan?.type == .workout
        let trainedToday = input.workoutDates.contains(todayKey)
        let yesterday = snapshot.days.last { $0.date == iso(addDays(-1, to: today)) }

        if input.dayFlags.contains(where: { $0.date == todayKey && $0.status == .sick }) {
            return CoachMessage(kind: .sick, text: "Sick day. Nothing to hit today: log what you eat when you can, and the normal plan starts when you're well.", action: nil, actionTitle: nil)
        }

        // A long run of off days gets one calm line, with no numbers piled on.
        if let run = snapshot.currentRun, !run.onPlan, run.length >= Self.roughStretchDays, yesterday != nil {
            return CoachMessage(kind: .roughStretch, text: "It's been a rough stretch. Don't go back with a crash day. Normal plan today, nothing more.", action: nil, actionTitle: nil)
        }

        let targetText = todayGoal.map { Int($0.dailyCalorieTarget).formatted() }
        let todayAction: (CoachMessage.Action, String) = isTrainingDay && !trainedToday
            ? (.startWorkout, "Start today's workout")
            : (.openNutrition(daysFromToday: 0), "Open today's meals")

        if let yesterday, !yesterday.isSick, yesterday.status == .flagged || yesterday.status == .over {
            var text = "Yesterday was off."
            if let stat = snapshot.condition(.afterSlip), stat.n >= Self.minSampleForWeakness {
                text += " After an off day you go off again \(percent(stat.offRate))% of the time."
            }
            text += " Today is a normal day"
            if let targetText { text += ": full \(targetText)" }
            if isTrainingDay, let hour = usualStartHour(weekday: weekday) { text += ", gym at \(Self.clock(hour))" }
            text += "."
            return CoachMessage(kind: .afterSlip, text: text, action: todayAction.0, actionTitle: todayAction.1)
        }

        if let yesterday, !yesterday.isSick, yesterday.status == .blank {
            let blanks = snapshot.counts.blank
            return CoachMessage(
                kind: .lowLogging,
                text: "Yesterday isn't fully logged. \(blanks) barely logged \(blanks == 1 ? "day" : "days") counted as off this phase. Finish it now: 2 minutes.",
                action: .openNutrition(daysFromToday: -1), actionTitle: "Open yesterday's meals"
            )
        }

        if isTrainingDay, !trainedToday, let stat = snapshot.weakness(.noTraining) {
            let usual = usualStartHour(weekday: weekday) ?? Self.fallbackStartHour
            let late = Double(calendar.component(.hour, from: input.now)) + Double(calendar.component(.minute, from: input.now)) / 60
            if late >= usual + Self.lateAfterUsualStartHours {
                let trainedRate = snapshot.condition(.noTraining)?.restRate ?? 0
                return CoachMessage(
                    kind: .noTraining,
                    text: "No \(plan?.title ?? "session") yet. Days without a session: \(percent(stat.offRate))% off plan. Days with one: \(percent(trainedRate))%.",
                    action: .startWorkout, actionTitle: "Start workout"
                )
            }
        }

        if let weak = snapshot.weakness(.weekday(weekday)) {
            return CoachMessage(
                kind: .weekday,
                text: "\(Self.weekdayName(weekday)): \(weak.off) of your last \(weak.n) went off plan. Is today's food planned?",
                action: .openNutrition(daysFromToday: 0), actionTitle: "Open today's meals"
            )
        }

        if let treat = input.plannedTreats.first(where: { $0.date == todayKey }) {
            return CoachMessage(
                kind: .treatDay,
                text: "Planned: \(treat.label), \(Int(treat.extraCalories)) kcal. It's in the numbers. Log it first, then enjoy it.",
                action: .logTreat, actionTitle: "Log treat"
            )
        }

        var text: String
        if let week = thisWeek(days: snapshot.days) {
            let finished = week.cells.compactMap(\.record)
            text = finished.isEmpty ? "New week." : "\(week.onCount) / \(finished.count) on plan this week."
        } else {
            text = "Day one."
        }
        var todayParts: [String] = []
        if let plan { todayParts.append(plan.title) }
        if let steps = todayGoal?.stepTarget, steps > 0 { todayParts.append("\(steps / 1000)k steps") }
        if !todayParts.isEmpty { text += " Today: " + todayParts.joined(separator: " + ") + "." }
        return CoachMessage(kind: .normal, text: text, action: nil, actionTitle: nil)
    }

    private func percent(_ rate: Double) -> Int { Int((rate * 100).rounded()) }

    /// 11.0 -> "11", 11.5 -> "11:30".
    static func clock(_ hour: Double) -> String {
        let total = Int((hour * 60).rounded())
        let h = total / 60, m = total % 60
        return m == 0 ? "\(h)" : String(format: "%d:%02d", h, m)
    }
}
