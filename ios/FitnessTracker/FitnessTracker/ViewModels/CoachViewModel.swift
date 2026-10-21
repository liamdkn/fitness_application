import Combine
import Foundation
import UIKit

/// A moment worth stopping for: a milestone, a freeze, a perfect week, or a streak that ended.
struct StreakMoment: Identifiable, Equatable {
    enum Kind: Equatable { case milestone, freezeUsed, freezeEarned, broken }
    let id: String
    let kind: Kind
    let headline: String
    let message: String
    /// The streak the moment is about, for the flame's size.
    let streak: Int
}

/// Gathers what the Coach needs from the existing repositories and hands it to the pure
/// `CoachEngine` and `StreakEngine`. Every query is scoped to the signed-in user by the
/// repositories (RLS).
///
/// Only the Dashboard's instance (`fireMoments`) records events and raises the full-screen
/// moments, so a moment shows once however many screens load the same data.
@MainActor
final class CoachViewModel: ObservableObject {
    @Published var snapshot: CoachSnapshot?
    @Published var message: CoachMessage?
    @Published var streak: StreakState?
    @Published var stars: StarState?
    /// Rows from the phase's first week to its last, so the star chart shows the stars still to earn.
    @Published var weeks: [CoachWeek] = []
    @Published var thisWeek: CoachWeek?
    /// The day whose star was just confirmed: its cell pulses once.
    @Published var celebratingDate: String?
    @Published var phaseType: GoalPhaseType?
    @Published var phaseStartedAt: String?
    /// The phase's last day.
    @Published var phaseEndDate: Date?
    /// Smoothed weight now and at the phase start.
    @Published var trendNowKg: Double?
    @Published var trendStartKg: Double?
    /// Every reward, and how far the ones in this phase are.
    @Published var rewards: [Reward] = []
    @Published var rewardProgress: [RewardProgress] = []
    @Published var moments: [StreakMoment] = []
    @Published var pendingUnlock: RewardProgress?
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let fireMoments: Bool

    init(fireMoments: Bool = false) { self.fireMoments = fireMoments }

    /// The last 14 finished days.
    var last14: (on: Int, of: Int)? {
        guard let days = snapshot?.days, !days.isEmpty else { return nil }
        let recent = days.suffix(14)
        return (recent.filter { $0.status.isOn }.count, recent.count)
    }

    /// Rewards still being worked towards, in this phase.
    var activeRewards: [RewardProgress] { rewardProgress.filter { !$0.isAchieved } }

    /// The closest reward to being earned.
    var nearestReward: RewardProgress? { activeRewards.max { $0.fraction < $1.fraction } }

    func dismissMoment() { if !moments.isEmpty { moments.removeFirst() } }

    private static let seenStarsKey = "coach.confirmedStarDates"

    func load() async {
        defer { isLoading = false }
        do {
            guard let current = try await GoalsRepository().fetchCurrentGoal() else {
                snapshot = nil
                message = nil
                return
            }
            let phaseGoals = try await GoalsRepository().fetchPastGoals(limit: 60).filter { $0.phaseStartedAt == current.phaseStartedAt }
            guard let start = DateFormatting.date(fromISODate: current.phaseStartedAt) else { return }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: start) ?? start

            var input = CoachInput(goals: phaseGoals.isEmpty ? [current] : phaseGoals)

            let nutrition = try await NutritionRepository().fetchDailyTotals(from: start, to: today)
            input.dailyCalories = Dictionary(nutrition.map { ($0.date, $0.calories) }, uniquingKeysWith: { _, latest in latest })
            input.dailyProtein = Dictionary(nutrition.map { ($0.date, $0.proteinG) }, uniquingKeysWith: { _, latest in latest })

            input.checkins = (try? await DailyCheckinRepository().fetchRange(from: dayBefore, to: today)) ?? []
            input.dayFlags = (try? await DayFlagRepository().fetchRange(from: start, to: today)) ?? []
            input.plannedTreats = (try? await PlannedTreatRepository().fetchTreats(from: start, to: today)) ?? []

            // Any workout row counts, however it got there (the app, HealthKit, or entered by hand).
            let workouts = try await WorkoutRepository().fetchWorkouts(from: start, to: tomorrow)
            input.workoutDates = Set(workouts.map { DateFormatting.isoDate($0.performedAt) })
            input.workoutStarts = workouts.map(\.startedAt)
            input.plan = await TrainingDayService().weekPlans()

            let engine = CoachEngine(input)
            let snapshot = engine.snapshot()
            self.snapshot = snapshot
            weeks = engine.calendarWeeks(days: snapshot.days, throughPhaseEnd: true)
            thisWeek = engine.thisWeek(days: snapshot.days)
            message = engine.message(snapshot: snapshot)
            phaseType = current.phaseType
            phaseStartedAt = current.phaseStartedAt
            phaseEndDate = calendar.date(byAdding: .day, value: current.durationWeeks * 7 - 1, to: start)

            let provisional = engine.todayProvisionallyOnPlan()
            let streakEngine = StreakEngine(
                days: snapshot.days, todayKey: DateFormatting.isoDate(today),
                provisionalToday: provisional, phaseLengthDays: current.durationWeeks * 7
            )
            let computed = streakEngine.compute()
            streak = computed.streak
            stars = computed.stars
            noteNewStars(computed.stars)

            // Rewards belong to a phase; only this phase's are worked out.
            let allRewards = (try? await RewardRepository().fetchAll()) ?? []
            rewards = allRewards
            rewardProgress = streakEngine.progress(for: allRewards.filter { $0.phaseStartedAt == nil || $0.phaseStartedAt == current.phaseStartedAt })

            if fireMoments {
                await recordMoments(streak: computed.streak, today: today)
                await settleRewards(today: today)
                let sickToday = input.dayFlags.contains { $0.date == DateFormatting.isoDate(today) && $0.status == .sick }
                await StreakNudgeService.shared.refresh(streak: computed.streak.current, provisionalToday: provisional, sickToday: sickToday)
            }

            let weights = (try? await BodyWeightRepository().fetchHistory(limit: 600)) ?? []
            let trend = TrendWeightCalculator.compute(from: weights)
            trendNowKg = trend.last?.weightKg
            trendStartKg = (trend.last { $0.date <= start } ?? trend.first { $0.date >= start })?.weightKg
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Stars

    /// Compares the confirmed stars with the ones seen last time. A star that wasn't there before
    /// (yesterday's, once this morning's check-in confirms it) pulses once, with a light tap.
    private func noteNewStars(_ stars: StarState) {
        let confirmed = Set(stars.byDate.filter { $0.value == .filled }.keys)
        let defaults = UserDefaults.standard
        let previous = defaults.stringArray(forKey: Self.seenStarsKey).map(Set.init)
        defaults.set(Array(confirmed), forKey: Self.seenStarsKey)
        // The first run only records what is there, so history doesn't all light up at once.
        guard let previous, let newest = confirmed.subtracting(previous).max() else { return }
        celebratingDate = newest
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if celebratingDate == newest { celebratingDate = nil }
        }
    }

    // MARK: Moments

    /// Stores each streak event once. Events from yesterday or today raise a moment; older ones
    /// (the history, the first time this runs) are recorded quietly. If storing fails (offline, or
    /// the migration not applied yet) nothing is raised, so a moment can't repeat on every load.
    private func recordMoments(streak: StreakState, today: Date) async {
        guard let added = try? await StreakEventRepository().recordNew(streak.events) else { return }
        let yesterday = DateFormatting.isoDate(Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today)
        let fresh = added.filter { $0.date >= yesterday }.sorted { ($0.date, $0.kind.rawValue) < ($1.date, $1.kind.rawValue) }
        guard !fresh.isEmpty else { return }
        moments.append(contentsOf: fresh.compactMap { moment(for: $0, streak: streak) })
    }

    /// Calm wording throughout. Never a nudge to eat less or do extra cardio to win a streak back.
    private func moment(for event: StreakEvent, streak: StreakState) -> StreakMoment? {
        let id = event.id
        switch event.kind {
        case .milestone:
            let days = event.value ?? 0
            var text = "\(days) days."
            if days > streak.bestBeforeCurrent {
                text += " Longest of this cut."
                if streak.bestBeforeCurrent > 0 { text += " Previous best: \(streak.bestBeforeCurrent)." }
            } else {
                text += " Best this cut: \(streak.best)."
            }
            return StreakMoment(id: id, kind: .milestone, headline: "\(days) days", message: text, streak: days)
        case .freezeUsed:
            let days = event.value ?? streak.current
            return StreakMoment(id: id, kind: .freezeUsed, headline: "Freeze used",
                                message: "Freeze used. Streak safe at \(days). Today has to be on plan.", streak: days)
        case .freezeEarned:
            return StreakMoment(id: id, kind: .freezeEarned, headline: "Perfect week",
                                message: "7 out of 7. You earned a streak freeze (\(streak.freezesBanked) banked).", streak: streak.current)
        case .broken:
            return StreakMoment(id: id, kind: .broken, headline: "Streak reset",
                                message: "Streak reset. Best this cut: \(streak.best) days. Day 1 starts with today's plan.", streak: 0)
        }
    }

    // MARK: Rewards

    /// Marks newly earned rewards (once, so they can't be taken back) and raises the unlock moment;
    /// a missed deadline just clears.
    private func settleRewards(today: Date) async {
        let repository = RewardRepository()
        var changed = false
        for progress in rewardProgress where progress.isAchieved && progress.reward.achievedAt == nil {
            if (try? await repository.markAchieved(id: progress.reward.id)) != nil {
                changed = true
                if pendingUnlock == nil { pendingUnlock = progress }
            }
        }
        let todayKey = DateFormatting.isoDate(today)
        for progress in rewardProgress where !progress.isAchieved {
            if let deadline = progress.reward.deadline, deadline < todayKey {
                if (try? await repository.clearDeadline(id: progress.reward.id)) != nil { changed = true }
            }
        }
        if changed, let refreshed = try? await repository.fetchAll() {
            rewards = refreshed
        }
    }

    func claim(_ reward: Reward) async {
        try? await RewardRepository().markClaimed(id: reward.id)
        pendingUnlock = nil
        if let refreshed = try? await RewardRepository().fetchAll() { rewards = refreshed }
    }
}
