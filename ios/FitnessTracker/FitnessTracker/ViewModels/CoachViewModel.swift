import Combine
import Foundation
import UIKit

/// Gathers what the Coach needs from the existing repositories and hands it to the pure
/// `CoachEngine`. Every query is scoped to the signed-in user by the repositories (RLS).
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
    /// Smoothed weight now and at the phase start.
    @Published var trendNowKg: Double?
    @Published var trendStartKg: Double?
    @Published var isLoading = true
    @Published var errorMessage: String?

    /// The last 14 finished days.
    var last14: (on: Int, of: Int)? {
        guard let days = snapshot?.days, !days.isEmpty else { return nil }
        let recent = days.suffix(14)
        return (recent.filter { $0.status.isOn }.count, recent.count)
    }

    private static let seenStarsKey = "coach.confirmedStarDates"

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

            let streakEngine = StreakEngine(
                days: snapshot.days, todayKey: DateFormatting.isoDate(today),
                provisionalToday: engine.todayProvisionallyOnPlan(), phaseLengthDays: current.durationWeeks * 7
            )
            let computed = streakEngine.compute()
            streak = computed.streak
            stars = computed.stars
            noteNewStars(computed.stars)

            let weights = (try? await BodyWeightRepository().fetchHistory(limit: 600)) ?? []
            let trend = TrendWeightCalculator.compute(from: weights)
            trendNowKg = trend.last?.weightKg
            trendStartKg = (trend.last { $0.date <= start } ?? trend.first { $0.date >= start })?.weightKg
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
