import Foundation
import Testing
@testable import FitnessTracker

@Suite @MainActor struct CoachEngineTests {
    private let target = 2000.0

    private func date(_ iso: String) -> Date { DateFormatting.date(fromISODate: iso)! }

    private func isoDay(_ start: String, plus offset: Int) -> String {
        DateFormatting.isoDate(Calendar.current.date(byAdding: .day, value: offset, to: date(start))!)
    }

    private func goal(from effective: String = "2026-08-17", phaseStart: String = "2026-08-17", calories: Double = 2000) -> UserGoal {
        UserGoal(id: UUID(), effectiveFrom: effective, phaseStartedAt: phaseStart, phaseType: .cut, startingWeightKg: 72,
                 durationWeeks: 12, dailyCalorieTarget: calories, proteinGTarget: 160, carbsGTarget: nil, fatGTarget: nil,
                 targetWeightKg: nil, weeklyWeightChangeKg: -0.5, stepTarget: 10000, sleepTargetMinutes: nil,
                 cardioSessionsPerWeek: 2, cardioMinutesPerSession: 30, strengthSessionsPerWeek: 4, strengthOptionalSessions: 1)
    }

    private func checkin(_ day: String, offPlan: Bool, hunger: Int? = nil, note: String? = nil) throws -> DailyCheckin {
        let hungerJSON = hunger.map(String.init) ?? "null"
        let noteJSON = note.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"id":"\(UUID().uuidString)","checkin_date":"\(day)","weight_kg":null,"routine_day_id":null,"workout_choice_label":null,
         "is_rest_day":false,"energy_level":null,"soreness_level":null,"yesterday_water_ml":null,
         "yesterday_off_plan":\(offPlan),"yesterday_off_plan_notes":\(noteJSON),"yesterday_hunger_level":\(hungerJSON)}
        """
        return try JSONDecoder().decode(DailyCheckin.self, from: Data(json.utf8))
    }

    private func treat(_ day: String, kcal: Double, label: String = "Choc bar") -> PlannedTreat {
        PlannedTreat(id: UUID(), date: day, mealSlotId: nil, label: label, extraCalories: kcal, extraProteinG: 0, extraCarbsG: 0, extraFatG: 0)
    }

    /// One finished day per entry from `start`, with `now` at midday on the day after the last one.
    /// Calories and the next morning's check-in are set so each day lands on its status.
    private func input(_ days: [(CoachDayStatus, Bool)], start: String = "2026-08-17", nowHour: Int = 12,
                       sick: Set<Int> = [], plan: [Int: TrainingDayService.DayPlan] = [:],
                       treats: [PlannedTreat] = []) throws -> CoachInput {
        var input = CoachInput(goals: [goal(phaseStart: start)])
        let nowDay = isoDay(start, plus: days.count)
        input.now = date(nowDay).addingTimeInterval(Double(nowHour) * 3600)
        for (offset, entry) in days.enumerated() {
            let day = isoDay(start, plus: offset)
            switch entry.0 {
            case .on, .flagged: input.dailyCalories[day] = target
            case .blank: input.dailyCalories[day] = 600
            case .over: input.dailyCalories[day] = target + 400
            }
            input.dailyProtein[day] = 150
            if entry.1 { input.workoutDates.insert(day) }
            input.checkins.append(try checkin(isoDay(start, plus: offset + 1), offPlan: entry.0 == .flagged))
            if sick.contains(offset) { input.dayFlags.append(DayFlag(date: day, status: .sick)) }
        }
        input.plan = plan
        input.plannedTreats = treats
        return input
    }

    // MARK: Acceptance fixture

    /// A 65-day fixture: 30 on / 21 flagged / 13 blank / 1 over,
    /// off-plan runs [1,3,3,1,6,1,2,2,1,9,6], 31 sessions of which 12 on off-plan days.
    private func longFixtureDays() -> [(CoachDayStatus, Bool)] {
        let gaps = [3, 2, 3, 2, 3, 2, 3, 3, 3, 3, 3]
        let runs = [1, 3, 3, 1, 6, 1, 2, 2, 1, 9, 6]
        var days: [(CoachDayStatus, Bool)] = []
        var onIndex = 0, offIndex = 0
        for run in 0..<gaps.count {
            for _ in 0..<gaps[run] {
                days.append((.on, (onIndex * 7 + 3) % 30 < 19))
                onIndex += 1
            }
            for _ in 0..<runs[run] {
                let rank = (offIndex * 11) % 35
                let status: CoachDayStatus = rank == 0 ? .over : (rank <= 13 ? .blank : .flagged)
                days.append((status, (offIndex * 13) % 35 < 12))
                offIndex += 1
            }
        }
        return days
    }

    @Test func theRealShapedFixtureReproducesTheAcceptanceNumbers() throws {
        let days = longFixtureDays()
        #expect(days.count == 65)
        let snapshot = CoachEngine(try input(days)).snapshot()

        #expect(snapshot.days.count == 65)
        #expect(snapshot.counts.on == 30)
        #expect(snapshot.counts.flagged == 21)
        #expect(snapshot.counts.blank == 13)
        #expect(snapshot.counts.over == 1)
        #expect(snapshot.offRuns.map(\.length) == [1, 3, 3, 1, 6, 1, 2, 2, 1, 9, 6])
        #expect(snapshot.longestOffRun == 9)

        let afterSlip = try #require(snapshot.condition(.afterSlip))
        #expect(afterSlip.restOff == 11 && afterSlip.restN == 30)
        #expect(afterSlip.off == 24 && afterSlip.n == 34)

        let noTraining = try #require(snapshot.condition(.noTraining))
        #expect(noTraining.restOff == 12 && noTraining.restN == 31)
        #expect(noTraining.off == 23 && noTraining.n == 34)

        // Only the two expected weaknesses. No weekday, no sleep or steps (they aren't modelled).
        #expect(Set(snapshot.weaknesses.map(\.kind)) == [.afterSlip, .noTraining])
    }

    @Test func sickDaysCountAsOffButStayOutOfTheRates() throws {
        // Two sick days inside off-plan runs.
        let days = longFixtureDays()
        let offDays = days.indices.filter { !days[$0].0.isOn }
        let sickDays: Set<Int> = [offDays[20], offDays[22]]
        let snapshot = CoachEngine(try input(days, sick: sickDays)).snapshot()

        // Totals and runs still see them as off.
        #expect(snapshot.counts.off == 35)
        #expect(snapshot.offRuns.map(\.length) == [1, 3, 3, 1, 6, 1, 2, 2, 1, 9, 6])
        #expect(snapshot.days.filter(\.isSick).count == 2)

        // The rates leave them out, and the day after each is not a behaviour signal either.
        let untrainedSick = sickDays.filter { !days[$0].1 }.count
        let noTraining = try #require(snapshot.condition(.noTraining))
        #expect(noTraining.n == 34 - untrainedSick)
        let afterSlip = try #require(snapshot.condition(.afterSlip))
        #expect(afterSlip.n < 34)

        #expect(snapshot.weakness(.afterSlip) != nil)
        #expect(snapshot.weakness(.noTraining) != nil)
    }

    // MARK: Classification

    @Test func flaggedBeatsBlankAndBlankBeatsOver() throws {
        var input = try input([(.on, false), (.on, false), (.on, false), (.on, false)])
        // Day 0: flagged and barely logged -> flagged. Day 1: barely logged -> blank. Day 2: over. Day 3: on.
        input.checkins = [try checkin("2026-08-18", offPlan: true), try checkin("2026-08-19", offPlan: false),
                          try checkin("2026-08-20", offPlan: false), try checkin("2026-08-21", offPlan: false)]
        input.dailyCalories = ["2026-08-17": 500, "2026-08-18": 1500, "2026-08-19": 2400, "2026-08-20": 2000]
        let statuses = CoachEngine(input).classifiedDays().map(\.status)
        #expect(statuses == [.flagged, .blank, .over, .on])
    }

    @Test func aDayIsBlankBelowEightyPercentAndOnAtExactlyEighty() throws {
        var input = try input([(.on, false), (.on, false)])
        input.dailyCalories = ["2026-08-17": target * 0.8 - 1, "2026-08-18": target * 0.8]
        #expect(CoachEngine(input).classifiedDays().map(\.status) == [.blank, .on])
    }

    @Test func aPlannedTreatWidensTheBudgetSoThatDayStaysOnPlan() throws {
        var input = try input([(.on, false), (.on, false)], treats: [treat("2026-08-17", kcal: 400)])
        // 2,500 is over target + 150 (2,290) but inside it once the 400 kcal treat is added (2,690).
        input.dailyCalories = ["2026-08-17": 2500, "2026-08-18": 2500]
        let days = CoachEngine(input).classifiedDays()
        #expect(days.map(\.status) == [.on, .over])
        #expect(days[0].isTreatDay && !days[1].isTreatDay)
    }

    @Test func theTargetInForceOnEachDayIsUsed() throws {
        var input = try input([(.on, false), (.on, false), (.on, false)])
        input.goals = [goal(calories: 2500), goal(from: "2026-08-18", calories: 1900)]
        // 1,900 kcal is under 80% of 2,500 (blank) but a full day once the target drops to 1,900.
        input.dailyCalories = ["2026-08-17": 1900, "2026-08-18": 1900, "2026-08-19": 1900]
        #expect(CoachEngine(input).classifiedDays().map(\.status) == [.blank, .on, .on])
    }

    @Test func todayIsNeverClassifiedAndADayClosesAtFourInTheMorning() throws {
        var input = try input([(.on, false), (.on, false)], nowHour: 12)
        // Without a check-in the day closes at 04:00 the next morning.
        input.checkins = []
        input.now = date("2026-08-19").addingTimeInterval(3 * 3600)
        #expect(CoachEngine(input).classifiedDays().map(\.date) == ["2026-08-17"])
        input.now = date("2026-08-19").addingTimeInterval(4 * 3600)
        #expect(CoachEngine(input).classifiedDays().map(\.date) == ["2026-08-17", "2026-08-18"])
        // A check-in closes the day straight away, but never today itself.
        input.now = date("2026-08-19").addingTimeInterval(1 * 3600)
        input.checkins = [try checkin("2026-08-19", offPlan: false)]
        #expect(CoachEngine(input).classifiedDays().map(\.date) == ["2026-08-17", "2026-08-18"])
    }

    @Test func aDayWithTwoWorkoutRowsStillCountsAsOneSession() throws {
        var input = try input([(.on, false)])
        input.workoutDates = Set(["2026-08-17", "2026-08-17"])
        let day = try #require(CoachEngine(input).classifiedDays().first)
        #expect(day.trained)
    }

    // MARK: Learning

    @Test func aConditionNeedsEightDaysBeforeItCanBeAWeakness() throws {
        // Seven off days after off days is not enough, even at 100%.
        let few: [(CoachDayStatus, Bool)] = [(.on, true)] + Array(repeating: (CoachDayStatus.flagged, true), count: 7)
        #expect(CoachEngine(try input(few)).snapshot().weaknesses.isEmpty)
        let enough: [(CoachDayStatus, Bool)] = [(.on, true)] + Array(repeating: (CoachDayStatus.flagged, true), count: 9) + [(.on, true), (.on, true), (.on, true)]
        let snapshot = CoachEngine(try input(enough)).snapshot()
        #expect(snapshot.weakness(.afterSlip) != nil)
    }

    @Test func aWeakWeekdayIsLearnedFromEnoughOfThem() throws {
        // 12 weeks, only Saturdays go off plan.
        var days: [(CoachDayStatus, Bool)] = []
        for offset in 0..<84 { days.append((offset % 7 == 5 ? .flagged : .on, true)) }   // the fixture starts on a Monday
        let snapshot = CoachEngine(try input(days)).snapshot()
        #expect(snapshot.weakness(.weekday(7)) != nil)
        #expect(snapshot.weakness(.weekday(2)) == nil)
    }

    @Test func hungerAtFourOrAboveIsLearnedFromTheNextMorningsCheckin() throws {
        var days: [(CoachDayStatus, Bool)] = []
        for offset in 0..<30 { days.append((offset % 3 == 0 ? .flagged : .on, true)) }
        var input = try input(days)
        input.checkins = try days.enumerated().map { offset, entry in
            let hungry = entry.0 == .flagged
            return try checkin(isoDay("2026-08-17", plus: offset + 1), offPlan: hungry, hunger: hungry ? 5 : 2)
        }
        let snapshot = CoachEngine(input).snapshot()
        let weak = try #require(snapshot.weakness(.highHunger))
        #expect(weak.n == 10 && weak.off == 10)
    }

    @Test func currentRunAndStreakFollowTheLatestDays() throws {
        let days: [(CoachDayStatus, Bool)] = [(.flagged, true), (.on, true), (.on, true), (.on, true)]
        let snapshot = CoachEngine(try input(days)).snapshot()
        #expect(snapshot.currentRun == CoachStreak(onPlan: true, length: 3))
        #expect(snapshot.onPlanStreak == 3)
        let off = CoachEngine(try input([(.on, true), (.blank, true), (.over, true)])).snapshot()
        #expect(off.currentRun == CoachStreak(onPlan: false, length: 2))
        #expect(off.onPlanStreak == 0)
    }

    // MARK: Calendar

    @Test func theCalendarRunsMondayToSundayWithNothingForTodayOrTheFuture() throws {
        // The fixture starts on a Monday: 10 finished days run through Wednesday of week 2.
        let days = Array(repeating: (CoachDayStatus.on, false), count: 10)
        let engine = CoachEngine(try input(days))
        let weeks = engine.calendarWeeks(days: engine.classifiedDays())
        #expect(weeks.count == 2)
        #expect(weeks[0].cells.compactMap(\.record).count == 7)
        #expect(weeks[1].cells.compactMap(\.record).count == 3)
        #expect(weeks[1].cells[3].isToday && weeks[1].cells[3].record == nil)
        #expect(weeks[1].cells[4].isFuture)
        #expect(weeks[0].onCount == 7)
    }

    // MARK: Today's message

    private let upperDay = TrainingDayService.DayPlan(type: .workout, title: "Upper B")
    private func fullWeekPlan(_ plan: TrainingDayService.DayPlan) -> [Int: TrainingDayService.DayPlan] {
        Dictionary(uniqueKeysWithValues: (1...7).map { ($0, plan) })
    }

    /// Words the coach must never say after an off day.
    private let forbidden = ["less", "skip", "cardio", "make up", "compensate", "deficit", "burn", "fast"]

    @Test func theDayAfterASlipSaysBackToTheNormalPlanAndNeverToMakeUpForIt() throws {
        // Plenty of history, so the after-a-slip rate is quoted.
        let engine = CoachEngine(try input(longFixtureDays() + [(.on, true), (.flagged, false)], plan: fullWeekPlan(upperDay)))
        let message = engine.message(snapshot: engine.snapshot())
        #expect(message.kind == .afterSlip)
        #expect(message.text.hasPrefix("Yesterday was off."))
        #expect(message.text.contains("Today is a normal day: full 2,000"))
        #expect(message.text.contains("% of the time"))
        #expect(message.action == .startWorkout)
        for word in forbidden { #expect(!message.text.lowercased().contains(word), "message says '\(word)'") }
    }

    @Test func aBlankYesterdayPointsToFinishingTheLog() throws {
        let engine = CoachEngine(try input([(.on, true), (.on, true), (.blank, false)]))
        let message = engine.message(snapshot: engine.snapshot())
        #expect(message.kind == .lowLogging)
        #expect(message.text.contains("isn't fully logged"))
        #expect(message.action == .openNutrition(daysFromToday: -1))
    }

    @Test func fiveOrMoreOffDaysInARowGetsTheCalmMessage() throws {
        let four = CoachEngine(try input([(.on, true)] + Array(repeating: (CoachDayStatus.flagged, false), count: 4)))
        #expect(four.message(snapshot: four.snapshot()).kind == .afterSlip)
        let five = CoachEngine(try input([(.on, true)] + Array(repeating: (CoachDayStatus.flagged, false), count: 5)))
        let message = five.message(snapshot: five.snapshot())
        #expect(message.kind == .roughStretch)
        #expect(message.text == "It's been a rough stretch. Don't go back with a crash day. Normal plan today, nothing more.")
        #expect(message.action == nil)
    }

    @Test func noSessionOnlyShowsOnceItIsTwoHoursPastTheUsualStart() throws {
        // Untrained days go off far more often, so no-session is a learned weakness.
        var days: [(CoachDayStatus, Bool)] = []
        for offset in 0..<40 { days.append(offset % 2 == 0 ? (.on, true) : (.flagged, false)) }
        days.append((.on, true))   // yesterday: on plan, so nothing outranks the session check
        var late = try input(days, nowHour: 14, plan: fullWeekPlan(upperDay))
        // Gym usually starts at 11:00 on this weekday.
        let weekdayToday = Calendar.current.component(.weekday, from: late.now)
        late.workoutStarts = (1...3).map { weeks in
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: late.now)
            parts.day! -= 7 * weeks
            parts.hour = 11
            return Calendar.current.date(from: parts)!
        }
        #expect(Calendar.current.component(.weekday, from: late.workoutStarts[0]) == weekdayToday)
        let engine = CoachEngine(late)
        #expect(engine.usualStartHour(weekday: weekdayToday) == 11)
        let message = engine.message(snapshot: engine.snapshot())
        #expect(message.kind == .noTraining)
        #expect(message.text.hasPrefix("No Upper B yet."))
        #expect(message.text.contains("Days with one:"))

        var early = late
        early.now = date(isoDay("2026-08-17", plus: days.count)).addingTimeInterval(12 * 3600)
        let earlyEngine = CoachEngine(early)
        #expect(earlyEngine.message(snapshot: earlyEngine.snapshot()).kind != .noTraining)

        var trained = late
        trained.workoutDates.insert(isoDay("2026-08-17", plus: days.count))
        let trainedEngine = CoachEngine(trained)
        #expect(trainedEngine.message(snapshot: trainedEngine.snapshot()).kind != .noTraining)
    }

    @Test func usualStartIsTheMedianOfTheLastFourWeeksOneSessionPerDate() throws {
        var input = try input([(.on, true)])
        let weekday = Calendar.current.component(.weekday, from: input.now)
        func start(weeksAgo: Int, hour: Int, minute: Int = 0) -> Date {
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: input.now)
            parts.day! -= 7 * weeksAgo
            parts.hour = hour
            parts.minute = minute
            return Calendar.current.date(from: parts)!
        }
        // Two rows the same day (HealthKit later than the manual one) count once; five weeks ago is ignored.
        input.workoutStarts = [start(weeksAgo: 1, hour: 10), start(weeksAgo: 1, hour: 18), start(weeksAgo: 2, hour: 12), start(weeksAgo: 3, hour: 11, minute: 30), start(weeksAgo: 5, hour: 6)]
        #expect(CoachEngine(input).usualStartHour(weekday: weekday) == 11.5)
        input.workoutStarts = []
        #expect(CoachEngine(input).usualStartHour(weekday: weekday) == nil)
    }

    @Test func aPlannedTreatTodayIsFramedAsPartOfThePlan() throws {
        let todayKey = isoDay("2026-08-17", plus: 3)
        let engine = CoachEngine(try input([(.on, true), (.on, true), (.on, true)], treats: [treat(todayKey, kcal: 350)]))
        let message = engine.message(snapshot: engine.snapshot())
        #expect(message.kind == .treatDay)
        #expect(message.text == "Planned: Choc bar, 350 kcal. It's in the numbers. Log it first, then enjoy it.")
        #expect(message.action == .logTreat)
    }

    @Test func aTreatDayThatStayedInBudgetIsNotASlipInTheNextMessage() throws {
        // Yesterday was a treat day, within budget: on plan, so no after-a-slip message.
        let yesterday = isoDay("2026-08-17", plus: 2)
        var input = try input([(.on, true), (.on, true), (.on, true)], treats: [treat(yesterday, kcal: 400)])
        input.dailyCalories[yesterday] = target + 450
        let engine = CoachEngine(input)
        #expect(engine.classifiedDays().last?.status == .on)
        #expect(engine.message(snapshot: engine.snapshot()).kind == .normal)
    }

    @Test func theNormalMessageQuotesTheWeekAndToday() throws {
        // Starts on a Monday; three finished days, all on plan, now Thursday.
        let plan = fullWeekPlan(TrainingDayService.DayPlan(type: .workout, title: "Lower B"))
        let engine = CoachEngine(try input([(.on, true), (.on, true), (.on, true)], plan: plan))
        let message = engine.message(snapshot: engine.snapshot())
        #expect(message.kind == .normal)
        #expect(message.text == "3 / 3 on plan this week. Today: Lower B + 10k steps.")
        #expect(message.action == nil)
    }

    @Test func aSickDayTodayGetsNoTargetsAtAll() throws {
        var input = try input([(.on, true), (.flagged, false)])
        input.dayFlags.append(DayFlag(date: isoDay("2026-08-17", plus: 2), status: .sick))
        let engine = CoachEngine(input)
        let message = engine.message(snapshot: engine.snapshot())
        #expect(message.kind == .sick)
        #expect(message.action == nil)
    }
}
