import Foundation
import Testing
@testable import FitnessTracker

@Suite @MainActor struct StreakEngineTests {
    /// The fixture starts on a Monday.
    private let start = "2026-08-17"

    private func key(_ offset: Int) -> String {
        let base = DateFormatting.date(fromISODate: start)!
        return DateFormatting.isoDate(Calendar.current.date(byAdding: .day, value: offset, to: base)!)
    }

    private func record(_ offset: Int, _ status: CoachDayStatus, sick: Bool = false) -> CoachDayRecord {
        let date = DateFormatting.date(fromISODate: key(offset))!
        return CoachDayRecord(
            date: key(offset), weekday: Calendar.current.component(.weekday, from: date), status: status, isSick: sick,
            trained: true, scheduledTraining: true, isTreatDay: false, hunger: nil, calories: 2000, proteinG: 160, target: 2000, note: nil
        )
    }

    /// One record per entry, starting on a Monday.
    private func days(_ statuses: [CoachDayStatus], sick: Set<Int> = []) -> [CoachDayRecord] {
        statuses.enumerated().map { record($0.offset, $0.element, sick: sick.contains($0.offset)) }
    }

    private func engine(_ statuses: [CoachDayStatus], sick: Set<Int> = [], provisional: Bool = false) -> StreakEngine {
        let list = days(statuses, sick: sick)
        return StreakEngine(days: list, todayKey: key(list.count), provisionalToday: provisional, phaseLengthDays: 84)
    }

    private func on(_ n: Int) -> [CoachDayStatus] { Array(repeating: .on, count: n) }

    // MARK: Acceptance fixture (65 days)

    /// On-plan runs [4,2,2,1,1,7,1,4,3,3,2] between off-plan runs [1,3,3,1,6,1,2,2,1,9,6]:
    /// 65 days, week 1 at 6/7, a 7-day run in week 4, the last six days off.
    private func longFixture() -> [CoachDayStatus] {
        let onRuns = [4, 2, 2, 1, 1, 7, 1, 4, 3, 3, 2]
        let offRuns = [1, 3, 3, 1, 6, 1, 2, 2, 1, 9, 6]
        var statuses: [CoachDayStatus] = []
        for index in onRuns.indices {
            statuses += on(onRuns[index])
            statuses += Array(repeating: CoachDayStatus.flagged, count: offRuns[index])
        }
        return statuses
    }

    @Test func theRealHistoryGivesThirtyStarsAndABestStreakOfSeven() {
        let statuses = longFixture()
        #expect(statuses.count == 65)
        let (streak, stars) = engine(statuses).compute()

        #expect(stars.total == 30)
        #expect(streak.best == 7)
        // Days 24 to 30 are the best run.
        let bestRun = (24...30).map { key($0) }
        #expect(bestRun.allSatisfy { stars.byDate[$0] == .filled })
        #expect(streak.current == 0)
        #expect(streak.brokenOn == key(64 - 5))   // the last off run starts six days from the end

        // No perfect week (week 1 was 6/7), so no freezes were ever earned and every slip broke the streak.
        #expect(stars.perfectWeeks.isEmpty)
        #expect(streak.freezesBanked == 0)
        #expect(streak.frozenDates.isEmpty)
        #expect(streak.events.filter { $0.kind == .broken }.compactMap(\.value) == [4, 2, 2, 1, 1, 7, 1, 4, 3, 3, 2])
        #expect(streak.milestonesHit == [3, 7])
    }

    @Test func todayIsStreakZeroWithAHollowStarOnceLoggedEnough() {
        let history = longFixture()
        let nothing = engine(history).compute()
        #expect(nothing.streak.displayCurrent == 0)
        #expect(nothing.stars.byDate[key(65)] == nil)

        let logged = engine(history, provisional: true).compute()
        #expect(logged.streak.current == 0)
        #expect(logged.streak.displayCurrent == 1)
        #expect(logged.stars.byDate[key(65)] == .provisional)
        // A provisional star isn't a confirmed one.
        #expect(logged.stars.total == 30)
    }

    // MARK: Freezes

    @Test func aSlipBreaksTheStreakWhenNoFreezeIsBanked() {
        let (streak, stars) = engine(on(5) + [.flagged] + on(1)).compute()
        #expect(streak.current == 1)
        #expect(streak.best == 5)
        #expect(stars.total == 6)
    }

    @Test func aPerfectWeekEarnsAFreezeThatSavesTheNextIsolatedSlip() {
        // Week 1 7/7 earns a freeze. Tuesday of week 2 slips: the freeze covers it.
        let (streak, stars) = engine(on(7) + on(1) + [.flagged] + on(1)).compute()
        #expect(stars.perfectWeeks == [key(0)])
        #expect(streak.current == 9)
        #expect(streak.best == 9)
        #expect(streak.freezesBanked == 0)
        #expect(streak.frozenDates == [key(8)])
        // The frozen day shows no star but isn't a gap either.
        #expect(stars.byDate[key(8)] == .frozen)
        #expect(stars.total == 9)
        #expect(streak.events.contains(StreakEvent(date: key(8), kind: .freezeUsed, value: 8)))
    }

    @Test func twoOffDaysInARowAlwaysBreakTheStreakEvenWithAFreeze() {
        let (streak, _) = engine(on(7) + [.flagged, .flagged] + on(2)).compute()
        #expect(streak.frozenDates == [key(7)])
        #expect(streak.events.contains(StreakEvent(date: key(8), kind: .broken, value: 7)))
        #expect(streak.current == 2)
        #expect(streak.best == 7)
    }

    @Test func aBlankDayCanNeverBeFrozen() {
        let (streak, _) = engine(on(7) + [.blank] + on(2)).compute()
        #expect(streak.frozenDates.isEmpty)
        #expect(streak.freezesBanked == 1)
        #expect(streak.current == 2)
        #expect(streak.events.contains(StreakEvent(date: key(7), kind: .broken, value: 7)))
    }

    @Test func overTargetCanBeFrozenLikeAFlaggedDay() {
        let (streak, _) = engine(on(7) + [.over] + on(1)).compute()
        #expect(streak.frozenDates == [key(7)])
        #expect(streak.current == 8)
    }

    @Test func freezesBankTwoAtMost() {
        let (streak, stars) = engine(on(21)).compute()
        #expect(stars.perfectWeeks.count == 3)
        #expect(streak.freezesBanked == 2)
        #expect(streak.events.filter { $0.kind == .freezeEarned }.count == 2)
    }

    @Test func aFreezeIsNotSpentWhenThereIsNoStreakToProtect() {
        let (streak, _) = engine(on(7) + [.flagged, .flagged, .flagged] + [.flagged]).compute()
        // First slip spends the freeze, the rest break and extend an already-zero streak.
        #expect(streak.frozenDates == [key(7)])
        let broken = streak.events.filter { $0.kind == .broken }
        #expect(broken.count == 1)
    }

    @Test func freezesAreEarnedNotFree() {
        // Without a perfect week the same slip pattern leaves the streak shorter.
        let withoutWeek = engine([.on, .on, .on, .on, .on, .on, .flagged, .on, .on, .flagged, .on]).compute().streak
        #expect(withoutWeek.frozenDates.isEmpty)
        #expect(withoutWeek.best == 6)
    }

    // MARK: Sick days

    @Test func sickDaysNeitherBreakNorAddToTheStreak() {
        let (streak, stars) = engine([.on, .on, .flagged, .on], sick: [2]).compute()
        #expect(streak.current == 3)
        #expect(stars.total == 3)
        #expect(stars.byDate[key(2)] == StarKind.none)
    }

    @Test func aSickDayStopsAWeekBeingPerfect() {
        let (streak, stars) = engine(on(7), sick: [3]).compute()
        #expect(stars.perfectWeeks.isEmpty)
        #expect(streak.freezesBanked == 0)
    }

    // MARK: Milestones

    @Test func milestonesAreRecordedOnTheDayTheyAreReached() {
        let (streak, _) = engine(on(8)).compute()
        let milestones = streak.events.filter { $0.kind == .milestone }
        #expect(milestones.map(\.value) == [3, 7])
        #expect(milestones.map(\.date) == [key(2), key(6)])
        #expect(streak.milestonesHit == [3, 7])
    }

    @Test func theBestBeforeTheCurrentStreakIsKept() {
        let (streak, _) = engine(on(7) + [.blank] + on(3)).compute()
        #expect(streak.best == 7)
        #expect(streak.bestBeforeCurrent == 7)
        #expect(streak.current == 3)
    }

    // MARK: Rewards

    private func reward(_ kind: RewardGoalKind, _ value: Double, achievedAt: Date? = nil) throws -> Reward {
        let json = """
        {"id":"\(UUID().uuidString)","title":"Prize","note":null,"photo_path":null,"price":null,"link":null,
         "goal_kind":"\(kind.rawValue)","goal_value":\(value),"phase_started_at":"\(start)","deadline":null,
         "achieved_at":null,"claimed_at":null,"created_at":"2026-08-17T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Reward.self, from: Data(json.utf8))
        return Reward(id: decoded.id, title: decoded.title, note: nil, photoPath: nil, price: nil, link: nil, goalKind: kind, goalValue: value,
                      phaseStartedAt: start, deadline: nil, achievedAt: achievedAt, claimedAt: nil, createdAt: decoded.createdAt)
    }

    @Test func starsRewardTracksConfirmedStars() throws {
        let progress = try engine(longFixture()).progress(for: [reward(.stars, 36)])[0]
        #expect(progress.value == 30 && progress.target == 36)
        #expect(!progress.isAchieved)
        #expect(progress.remainingText == "6 on-plan days to go")
        let done = try engine(longFixture()).progress(for: [reward(.stars, 30)])[0]
        #expect(done.isAchieved)
    }

    @Test func streakRewardIsAchievedByTheBestStreakButShowsTheCurrentOne() throws {
        let progress = try engine(longFixture()).progress(for: [reward(.streak, 7)])[0]
        #expect(progress.isAchieved)          // the 7-day run counts
        #expect(progress.value == 0)          // the bar tracks the current streak
        #expect(progress.best == 7)
        let longer = try engine(longFixture()).progress(for: [reward(.streak, 14)])[0]
        #expect(!longer.isAchieved)
    }

    @Test func perfectWeeksRewardCountsWholeWeeks() throws {
        let progress = try engine(on(14) + [.flagged]).progress(for: [reward(.perfectWeeks, 2)])[0]
        #expect(progress.value == 2 && progress.isAchieved)
    }

    @Test func phaseCompleteNeedsTheWholePhaseToHaveRun() throws {
        // 84-day phase. 70 days in at 80%: not finished, so not achieved however good the share.
        let early = try engine(on(60) + Array(repeating: CoachDayStatus.flagged, count: 10)).progress(for: [reward(.phaseComplete, 85)])[0]
        #expect(early.value == 85)
        #expect(!early.isAchieved)
        let finished = try engine(on(72) + Array(repeating: CoachDayStatus.flagged, count: 12)).progress(for: [reward(.phaseComplete, 85)])[0]
        #expect(finished.value == 85 && finished.isAchieved)
        let short = try engine(on(60) + Array(repeating: CoachDayStatus.flagged, count: 24)).progress(for: [reward(.phaseComplete, 85)])[0]
        #expect(short.value == 71 && !short.isAchieved)
    }

    @Test func aRewardAlreadyAchievedCannotBeTakenBack() throws {
        // Persisted as achieved; today's numbers fall short, but it stays earned.
        let progress = try engine(on(2)).progress(for: [reward(.stars, 30, achievedAt: Date())])[0]
        #expect(progress.isAchieved)
    }
}

@Suite struct StreakNudgePlanTests {
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute)
        parts.calendar = Calendar.current
        return parts.date!
    }

    @Test func remindsAtHalfPastNineWhenAStreakIsAtRisk() throws {
        let reminder = try #require(StreakNudgePlan.reminder(streak: 12, provisionalToday: false, sickToday: false, now: at(18)))
        #expect(reminder.fireDate == at(21, 30))
        #expect(reminder.body == "\u{1F525} 12-day streak. Log the rest of today to keep it.")
    }

    @Test func staysQuietWhenThereIsNothingToKeepOrTodayIsAlreadyFine() {
        #expect(StreakNudgePlan.reminder(streak: 0, provisionalToday: false, sickToday: false, now: at(18)) == nil)
        #expect(StreakNudgePlan.reminder(streak: 12, provisionalToday: true, sickToday: false, now: at(18)) == nil)
        #expect(StreakNudgePlan.reminder(streak: 12, provisionalToday: false, sickToday: true, now: at(18)) == nil)
    }

    @Test func doesNotFireOnceHalfPastNineHasPassed() {
        #expect(StreakNudgePlan.reminder(streak: 12, provisionalToday: false, sickToday: false, now: at(21, 45)) == nil)
    }
}
