import Foundation

// Pure streak, star and reward-progress maths on top of `CoachEngine`'s finished days. One
// chronological pass, recomputed from scratch on every load; only the events it reports
// (milestones, freezes, breaks) are worth persisting. See docs/streaks-and-rewards-plan.md.

enum StarKind: Equatable {
    /// An on-plan day, confirmed.
    case filled
    /// Today, looking on plan so far. Fills in once the next morning's check-in confirms it.
    case provisional
    /// An off-plan day a freeze covered: no star, but the streak survived it.
    case frozen
    case none
}

struct StreakEvent: Equatable, Identifiable {
    enum Kind: String { case milestone, freezeEarned = "freeze_earned", freezeUsed = "freeze_used", broken }
    /// ISO date the event happened on.
    let date: String
    let kind: Kind
    /// Milestone length, the streak a freeze protected, or the streak that ended.
    let value: Int?
    var id: String { "\(date)-\(kind.rawValue)" }
}

struct StreakState {
    /// Consecutive confirmed on-plan days ending yesterday.
    let current: Int
    let best: Int
    /// The best streak before the current one began - what a milestone message compares against.
    let bestBeforeCurrent: Int
    let freezesBanked: Int
    let frozenDates: [String]
    /// The most recent day a streak ended on.
    let brokenOn: String?
    let milestonesHit: [Int]
    let events: [StreakEvent]
    /// Today looks on plan so far.
    let provisionalToday: Bool

    /// What to show: the confirmed streak, plus today once it provisionally qualifies.
    var displayCurrent: Int { current + (provisionalToday ? 1 : 0) }
}

struct StarState {
    let total: Int
    /// ISO date -> what that day's cell shows.
    let byDate: [String: StarKind]
    /// The Mondays of weeks where all seven days were on plan.
    let perfectWeeks: [String]
}

struct RewardProgress: Identifiable {
    let reward: Reward
    let value: Int
    let target: Int
    /// Streak goals also show the best so far.
    let best: Int?
    let isAchieved: Bool
    /// "8 on-plan days to go".
    let remainingText: String

    var id: UUID { reward.id }
    var fraction: Double { target == 0 ? 0 : min(Double(value) / Double(target), 1) }
}

struct StreakEngine {
    static let milestones = [3, 7, 14, 21, 30, 45, 60, 90]
    static let maxFreezesBanked = 2

    let days: [CoachDayRecord]
    /// ISO date of today.
    let todayKey: String
    let provisionalToday: Bool
    /// Length of the phase in days, for "finish the phase" goals.
    let phaseLengthDays: Int

    init(days: [CoachDayRecord], todayKey: String, provisionalToday: Bool = false, phaseLengthDays: Int = 0) {
        self.days = days
        self.todayKey = todayKey
        self.provisionalToday = provisionalToday
        self.phaseLengthDays = phaseLengthDays
    }

    private var calendar: Calendar { Calendar.current }

    // MARK: One pass

    /// Sick days are neutral. An on-plan day extends the streak. An off-plan day breaks it, unless
    /// it is an isolated slip (the day before wasn't off) and a freeze is banked: then the streak
    /// survives. A barely logged day always breaks it. A streak that is already zero has nothing
    /// to protect, so no freeze is spent. Every perfect Monday-Sunday week banks a freeze (two at most).
    func compute() -> (streak: StreakState, stars: StarState) {
        var current = 0, best = 0, bestBeforeCurrent = 0, banked = 0
        var previousWasOff = false
        var brokenOn: String?
        var frozen: [String] = []
        var events: [StreakEvent] = []
        var milestonesHit: [Int] = []
        var byDate: [String: StarKind] = [:]
        var perfectWeeks: [String] = []
        var stars = 0
        let byKey = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })

        for day in days {
            byDate[day.date] = StarKind.none
            if day.isSick {
                // Neutral: no star, no progress, no break.
            } else if day.status.isOn {
                if current == 0 { bestBeforeCurrent = best }
                current += 1
                best = max(best, current)
                stars += 1
                previousWasOff = false
                byDate[day.date] = .filled
                if Self.milestones.contains(current) {
                    events.append(StreakEvent(date: day.date, kind: .milestone, value: current))
                    if !milestonesHit.contains(current) { milestonesHit.append(current) }
                }
            } else {
                let freezable = day.status != .blank && !previousWasOff && current > 0 && banked > 0
                if freezable {
                    banked -= 1
                    frozen.append(day.date)
                    byDate[day.date] = .frozen
                    events.append(StreakEvent(date: day.date, kind: .freezeUsed, value: current))
                } else {
                    if current > 0 {
                        events.append(StreakEvent(date: day.date, kind: .broken, value: current))
                        brokenOn = day.date
                    }
                    current = 0
                }
                previousWasOff = true
            }

            // A perfect week closes on its Sunday.
            if day.weekday == 1, let monday = mondayKey(endingOn: day.date) {
                let week = (0..<7).compactMap { offset in dateKey(monday, plus: offset).flatMap { byKey[$0] } }
                if week.count == 7, week.allSatisfy({ $0.status.isOn && !$0.isSick }) {
                    perfectWeeks.append(monday)
                    if banked < Self.maxFreezesBanked {
                        banked += 1
                        events.append(StreakEvent(date: day.date, kind: .freezeEarned, value: nil))
                    }
                }
            }
        }

        if provisionalToday, byDate[todayKey] == nil { byDate[todayKey] = .provisional }

        let streak = StreakState(
            current: current, best: best, bestBeforeCurrent: bestBeforeCurrent, freezesBanked: banked,
            frozenDates: frozen, brokenOn: brokenOn, milestonesHit: milestonesHit.sorted(),
            events: events, provisionalToday: provisionalToday
        )
        return (streak, StarState(total: stars, byDate: byDate, perfectWeeks: perfectWeeks))
    }

    // MARK: Rewards

    /// How far each reward is. Only confirmed days count, so a reward can't be earned and then
    /// taken back by a day that later turns out off plan. A reward already marked achieved stays so.
    func progress(for rewards: [Reward]) -> [RewardProgress] {
        let (streak, stars) = compute()
        let onShare = days.isEmpty ? 0 : Int((Double(stars.total) / Double(days.count) * 100).rounded(.down))
        let phaseFinished = phaseLengthDays > 0 && days.count >= phaseLengthDays

        return rewards.map { reward in
            let target = Int(reward.goalValue.rounded())
            let value: Int, achieved: Bool, remaining: String, best: Int?
            switch reward.goalKind {
            case .stars:
                value = stars.total; best = nil
                achieved = value >= target
                remaining = "\(max(target - value, 0)) on-plan day\(target - value == 1 ? "" : "s") to go"
            case .streak:
                value = streak.displayCurrent; best = streak.best
                achieved = streak.best >= target
                remaining = "best so far \(streak.best)"
            case .perfectWeeks:
                value = stars.perfectWeeks.count; best = nil
                achieved = value >= target
                remaining = "\(max(target - value, 0)) perfect week\(target - value == 1 ? "" : "s") to go"
            case .phaseComplete:
                value = onShare; best = nil
                achieved = phaseFinished && onShare >= target
                remaining = phaseFinished ? "phase finished at \(onShare)%" : "\(onShare)% on plan so far"
            }
            return RewardProgress(
                reward: reward, value: value, target: target, best: best,
                isAchieved: reward.achievedAt != nil || achieved, remainingText: remaining
            )
        }
    }

    // MARK: Dates

    private func dateKey(_ iso: String, plus offset: Int) -> String? {
        DateFormatting.date(fromISODate: iso)
            .flatMap { calendar.date(byAdding: .day, value: offset, to: $0) }
            .map(DateFormatting.isoDate)
    }

    /// The Monday of the week ending on this Sunday.
    private func mondayKey(endingOn sunday: String) -> String? { dateKey(sunday, plus: -6) }
}
