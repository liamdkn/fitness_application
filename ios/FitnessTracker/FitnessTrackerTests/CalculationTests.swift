import Foundation
import Testing
@testable import FitnessTracker

/// The maths the app's numbers rest on. These are pure functions, so they run
/// instantly and never touch the network.
struct MacroEnergyTests {
    @Test func macrosThatAddUpAreConsistent() {
        // 30 P + 50 C + 10 F = 120 + 200 + 90 = 410 kcal
        let check = MacroEnergy.check(calories: 410, protein: 30, carbs: 50, fat: 10)
        #expect(check.isConsistent)
        #expect(abs(check.unassignedKcal) < 0.001)
    }

    @Test func missingMacroShowsAsUnassignedCalories() {
        let check = MacroEnergy.check(calories: 1000, protein: 16, carbs: 0, fat: 0)
        #expect(!check.isConsistent)
        #expect(check.unassignedKcal == 1000 - 64)
    }

    @Test func labelToleranceIsLooserThanStrict() {
        let strict = MacroEnergy.check(calories: 450, protein: 30, carbs: 50, fat: 10, tolerance: .strict)
        let label = MacroEnergy.check(calories: 450, protein: 30, carbs: 50, fat: 10, tolerance: .label)
        #expect(!strict.isConsistent)
        #expect(label.isConsistent)
    }
}

struct MealFitterTests {
    typealias M = MealFitter.Macros

    @Test func solvesProteinCarbAndFatTargetsTogether() {
        // Per 100 g: chicken 31P/3.6F, rice 2.7P/28C/0.3F, oil 100F.
        let chicken = MealFitter.Line(perServing: M(calories: 165, protein: 31, carbs: 0, fat: 3.6), servings: 1.5)
        let rice = MealFitter.Line(perServing: M(calories: 130, protein: 2.7, carbs: 28, fat: 0.3), servings: 1.5)
        let oil = MealFitter.Line(perServing: M(calories: 884, protein: 0, carbs: 0, fat: 100), servings: 0.1)
        let scale = MealFitter.fit(
            protein: [chicken], carbs: [rice], fat: [oil], fixed: [],
            targets: .init(protein: 50, carbs: 80, fat: 15)
        )
        let protein = 31 * 1.5 * scale.protein + 2.7 * 1.5 * scale.carbs
        let carbs = 28 * 1.5 * scale.carbs
        let fat = 3.6 * 1.5 * scale.protein + 0.3 * 1.5 * scale.carbs + 100 * 0.1 * scale.fat
        #expect(abs(protein - 50) < 0.1)
        #expect(abs(carbs - 80) < 0.1)
        #expect(abs(fat - 15) < 0.1)
    }

    @Test func leavesAGroupAloneWithoutATarget() {
        let rice = MealFitter.Line(perServing: M(calories: 130, protein: 2.7, carbs: 28, fat: 0.3), servings: 1)
        let scale = MealFitter.fit(protein: [], carbs: [rice], fat: [], fixed: [], targets: .init(protein: nil, carbs: nil, fat: nil))
        #expect(scale.carbs == 1)
    }

    @Test func sizesAreNeverNegative() {
        // Fixed foods already overshoot the carb target.
        let rice = MealFitter.Line(perServing: M(calories: 130, protein: 2.7, carbs: 28, fat: 0.3), servings: 1)
        let bread = MealFitter.Line(perServing: M(calories: 265, protein: 9, carbs: 49, fat: 3), servings: 3)
        let scale = MealFitter.fit(protein: [], carbs: [rice], fat: [], fixed: [bread], targets: .init(protein: nil, carbs: 50, fat: nil))
        #expect(scale.carbs >= 0)
    }
}

struct PreworkoutCarbsTests {
    @Test func targetIsGramsPerKgOfBodyweight() {
        #expect(PreworkoutCarbs.targetG(weightKg: 71.1, gramsPerKg: 1.0) == 71)
        #expect(PreworkoutCarbs.targetG(weightKg: 80, gramsPerKg: 1.5) == 120)
    }

    @Test func noTargetWithoutWeightOrWhenTurnedOff() {
        #expect(PreworkoutCarbs.targetG(weightKg: nil, gramsPerKg: 1) == nil)
        #expect(PreworkoutCarbs.targetG(weightKg: 80, gramsPerKg: 0) == nil)
    }
}

struct WaterPaceTests {
    @Test func paceClimbsStraightFromWakeToTheEndOfTheDay() {
        let wake = 7 * 60, end = 19 * 60
        #expect(WaterPace.expectedMl(atMinute: wake, wakeMinutes: wake, endMinutes: end, targetMl: 3000) == 0)
        #expect(WaterPace.expectedMl(atMinute: 13 * 60, wakeMinutes: wake, endMinutes: end, targetMl: 3000) == 1500)
        #expect(WaterPace.expectedMl(atMinute: 22 * 60, wakeMinutes: wake, endMinutes: end, targetMl: 3000) == 3000)
    }

    @Test func catchUpIsAtLeastOneGlass() {
        #expect(WaterPace.glassesToCatchUp(behindMl: 40, glassMl: 250) == 1)
        #expect(WaterPace.glassesToCatchUp(behindMl: 600, glassMl: 250) == 3)
    }
}

struct CheckinGapsTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ iso: String) -> Date { DateFormatting.date(fromISODate: iso)! }

    @Test func countsConsecutiveMissedDaysBackFromYesterday() {
        let logged: Set<String> = ["2026-09-28", "2026-09-29"]
        // Today is 2 Oct: 1 Oct and 30 Sep are empty, 29 Sep has an entry.
        #expect(CheckinGaps.consecutiveMissed(logged: logged, today: date("2026-10-02")) == 2)
    }

    @Test func todayDoesNotCountAsMissed() {
        #expect(CheckinGaps.consecutiveMissed(logged: ["2026-10-01"], today: date("2026-10-02")) == 0)
    }

    @Test func findsTheGapBetweenTwoWeighIns() {
        let gap = CheckinGaps.gap(between: date("2026-09-20"), and: date("2026-09-24"))
        #expect(gap?.days == 3)
        #expect(CheckinGaps.gap(between: date("2026-09-20"), and: date("2026-09-21")) == nil)
    }
}

struct BedtimeAndCaffeineTests {
    @Test func smallHoursCountAsTheSameNight() {
        // 00:30 sorts after 23:30, so the typical bedtime isn't dragged to noon.
        let night = [23 * 60 + 30, 24 * 60 + 30, 23 * 60 + 45, 24 * 60 + 10]
        let typical = BedtimeEstimate.typicalBedtime(nightMinutes: night)
        #expect(typical != nil)
        #expect(typical! < 60 || typical! > 23 * 60)
    }

    @Test func needsAFewNightsBeforeCallingItAPattern() {
        #expect(BedtimeEstimate.typicalBedtime(nightMinutes: [1380, 1400]) == nil)
    }

    @Test func caffeineHalvesEveryHalfLife() {
        let now = Date()
        let dose = CaffeineModel.Dose(time: now.addingTimeInterval(-5 * 3600), mg: 200)
        let level = CaffeineModel.level(at: now, doses: [dose], halfLifeHours: 5)
        #expect(abs(level - 100) < 0.001)
    }

    @Test func aFutureDoseHasNotHappenedYet() {
        let now = Date()
        let dose = CaffeineModel.Dose(time: now.addingTimeInterval(3600), mg: 200)
        #expect(CaffeineModel.level(at: now, doses: [dose], halfLifeHours: 5) == 0)
    }
}

struct FoodAndRunFormattingTests {
    @Test func measuredFoodsShowRealAmounts() {
        #expect(AmountLabel.text(quantity: 0.8, servingSize: 100, servingUnit: "g", servingLabel: "100g") == "80g")
        #expect(AmountLabel.text(quantity: 2, servingSize: 1, servingUnit: "egg", servingLabel: "1egg") == "2 egg")
    }

    @Test func proteinHeavyFoodsAreProteinSources() {
        let roles = FoodCategory.suggested(calories: 165, proteinG: 31, carbsG: 0, fatG: 3.6)
        #expect(roles == [.protein])
    }

    @Test func salmonIsBothProteinAndFat() {
        let roles = FoodCategory.suggested(calories: 208, proteinG: 20, carbsG: 0, fatG: 13)
        #expect(roles.contains(.protein) && roles.contains(.fat))
    }

    @Test func pacesParseAndFormatAsMinutesAndSeconds() {
        #expect(PaceText.parse("5:30") == 330)
        #expect(PaceText.parse("5.5") == nil)
        #expect(PaceText.parse("0:30") == nil)
        #expect(PaceText.format(330) == "5:30/km")
    }
}

@Suite struct ScaleUnitAndGoalTests {
    @Test func standardScalePacketsDecodeToGrams() {
        // flags 0 (kg), raw 0x0064 = 100 x 0.005 kg = 0.5 kg = 500 g
        #expect(ScaleDecoding.standardWeightScale(Data([0x00, 0x64, 0x00])) == 500)
        #expect(ScaleDecoding.standardWeightScale(Data([0x00])) == nil)
    }
}

struct IcomonKitchenScaleTests {
    @Test func handshakeMatchesTheDocumentedFrame() {
        #expect(ScaleDecoding.hex(ScaleDecoding.icomonHandshake) == "AC 42 00 02 00 A0 00 D1 73")
    }

    @Test func milkMillilitreUnitCommandMatchesTheDocumentedFrame() {
        #expect(ScaleDecoding.hex(ScaleDecoding.icomonUnit(5)) == "AC 42 00 02 00 02 05 D2 DB")
    }

    @Test func scaleUnitFollowsTheFood() {
        #expect(ScaleDecoding.preferredScaleUnit(foodName: "Whole Milk", foodUnit: "ml") == 5)
        #expect(ScaleDecoding.preferredScaleUnit(foodName: "Orange Juice", foodUnit: "ml") == 1)
        #expect(ScaleDecoding.preferredScaleUnit(foodName: "Oats", foodUnit: "g") == 0)
        #expect(ScaleDecoding.preferredScaleUnit(foodName: "Banana", foodUnit: "medium") == nil)
    }

    @Test func tareCommandMatchesTheDocumentedFrame() {
        #expect(ScaleDecoding.hex(ScaleDecoding.icomonTare) == "AC 42 00 02 00 00 00 D2 D4")
    }

    @Test func readHistoryCommandMatchesTheDocumentedFrame() {
        #expect(ScaleDecoding.hex(ScaleDecoding.icomonCommand(payload: [0x00, 0x00], command: 0xD4)) == "AC 42 00 00 D4 D4")
    }

    @Test func userInfoMatchesTheFrameThatStartedTheWeightStream() {
        #expect(ScaleDecoding.hex(ScaleDecoding.icomonUserInfo) == "AC 42 00 04 00 00 00 00 01 DB E0")
    }

    @Test func decodesFramesCapturedFromARealScale() {
        // From a KN2432LB with a 55 g weight on it, then a heavier one.
        func parse(_ hex: String) -> ScaleDecoding.IcomonWeight? {
            let bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            return ScaleDecoding.icomonFrame(Data(bytes)).flatMap(ScaleDecoding.icomonWeight)
        }
        let settled55 = parse("ac 42 00 0e 00 01 00 00 d6 d8 00 00 00 00 00 00 00 00 00 a6 63")
        #expect(settled55?.grams == 55.0)
        #expect(settled55?.isMetric == true)
        #expect(parse("ac 42 00 0e 00 00 00 04 da 30 00 00 00 00 00 00 00 00 00 a6 c2")?.grams == 318.0)
        #expect(parse("ac 42 00 0e 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 a6 b4")?.grams == 0.0)
        // The scale switched to millilitres: still usable.
        #expect(parse("ac 42 00 0e 00 00 10 00 00 00 00 00 00 00 00 00 00 00 00 a6 c4")?.unit == 1)
        #expect(settled55?.settled == true)
        #expect(parse("ac 42 00 0e 00 00 00 04 da 30 00 00 00 00 00 00 00 00 00 a6 c2")?.settled == false)
    }

    @Test func aPickedFoodIdIsReadFromTheWeightMessage() {
        // Captured while flicking the scale's arrows: food id 18367, with a made-up 63 g.
        let frame = ScaleDecoding.icomonFrame(Data("ac 42 00 0e 00 00 10 00 f6 18 00 00 47 bf 00 00 00 00 00 a6 d8".split(separator: " ").compactMap { UInt8($0, radix: 16) }))
        let weight = frame.flatMap(ScaleDecoding.icomonWeight)
        #expect(weight?.foodId == 18367)
        #expect(weight?.grams == 63.0)
        let plain = ScaleDecoding.icomonFrame(Data("ac 42 00 0e 00 01 00 00 3e 80 00 00 00 00 00 00 00 00 00 a6 73".split(separator: " ").compactMap { UInt8($0, radix: 16) }))
        #expect(plain.flatMap(ScaleDecoding.icomonWeight)?.foodId == 0)
    }

    @Test func aMinusSignIsNegativeWeightNotMovement() {
        // Captured after a TARE with a bowl on: lifting the bowl gave a steady 0x80 reading of 16 g.
        let lifted = ScaleDecoding.icomonFrame(Data("ac 42 00 0e 00 80 00 00 3e 80 00 00 00 00 00 00 00 00 00 a6 f2".split(separator: " ").compactMap { UInt8($0, radix: 16) }))
        let weight = lifted.flatMap(ScaleDecoding.icomonWeight)
        #expect(weight?.grams == -16.0)
        #expect(weight?.isNegative == true)
    }

    @Test func tareIsADropFromASettledWeightStraightToZero() {
        var detector = ScaleDecoding.TareDetector()
        // From the capture: 17 g settled, then 0 g.
        #expect(detector.feed(grams: 17, settled: false) == nil)
        #expect(detector.feed(grams: 17, settled: true) == nil)
        #expect(detector.feed(grams: 0, settled: true) == 17)
        #expect(detector.feed(grams: 0, settled: false) == nil)
    }

    @Test func liftingAndReplacingABowlOnATaredScaleIsNotATare() {
        var detector = ScaleDecoding.TareDetector()
        // Bowl lifted: 0 then -16, steady. Put back: -6, -2, 0.
        for (grams, settled) in [(0.0, true), (-16.0, false), (-16.0, true), (-6.0, false), (-2.0, false), (0.0, true)] {
            #expect(detector.feed(grams: grams, settled: settled) == nil)
        }
    }

    @Test func decodesALiveWeightFrame() {
        // Header (length 14, seq 0), flags 1 (settled), unit 0, 99000 mg = 99 g, then the rest.
        let payload: [UInt8] = [0x00, 0x0E, 0x00, 0x01, 0x00, 0x01, 0x82, 0xB8,
                                0, 0, 0, 0, 0, 0, 0, 0, 0x01]
        let frame = ScaleDecoding.icomonCommand(payload: payload, command: 0xA6)
        let parsed = ScaleDecoding.icomonFrame(frame)
        #expect(parsed?.checksumOK == true)
        #expect(parsed.flatMap(ScaleDecoding.icomonWeight)?.grams == 99.0)
        #expect(parsed.flatMap(ScaleDecoding.icomonWeight)?.settled == true)
    }

    @Test func foodInMillilitresFollowsTheScalesMilkSetting() {
        #expect(abs((ScaleDecoding.amount(forGrams: 103, foodUnit: "ml", scaleUnit: 5) ?? 0) - 100) < 0.0001)
        #expect(ScaleDecoding.amount(forGrams: 100, foodUnit: "ml", scaleUnit: 1) == 100)
        #expect(ScaleDecoding.amount(forGrams: 100, foodUnit: "ml", scaleUnit: 0) == 100)
    }

    @Test func foodInGramsIsAlwaysTheMass() {
        #expect(ScaleDecoding.amount(forGrams: 50, foodUnit: "g", scaleUnit: 5) == 50)
        #expect(ScaleDecoding.amount(forGrams: 50, foodUnit: "g", scaleUnit: 3) == 50)
        #expect(ScaleDecoding.amount(forGrams: 50, foodUnit: "slice", scaleUnit: 0) == nil)
    }

    @Test func unitNamesMatchTheScalesCycle() {
        #expect(ScaleDecoding.unitName(0) == "g")
        #expect(ScaleDecoding.unitName(5) == "ml (milk)")
        #expect(ScaleDecoding.unitName(2) == "lb:oz")
    }

    @Test func goalStatusUsesAToleranceBandAroundTheTarget() {
        // 50 g: the band is about 48.5 ... 51.5
        #expect(GoalWeigh.status(amount: 50.7, target: 50) == .onTarget)
        #expect(GoalWeigh.status(amount: 48.6, target: 50) == .onTarget)
        #expect(GoalWeigh.status(amount: 51.4, target: 50) == .onTarget)
        #expect(GoalWeigh.status(amount: 40, target: 50) == .under(remaining: 10))
        #expect(GoalWeigh.status(amount: 55, target: 50) == .over(by: 5))
    }

    @Test func smallTargetsKeepAOneGramBand() {
        #expect(GoalWeigh.tolerance(for: 10) == 1.0)
        #expect(abs(GoalWeigh.tolerance(for: 200) - 6.0) < 0.0001)
    }
}

@Suite struct PreworkoutPlanTests {
    private let session = Date(timeIntervalSince1970: 1_000_000)

    @Test func earlierCarbsFadeWithTheHoursBeforeTheSession() {
        let justAte = PreworkoutPlan.Earlier(carbsG: 60, time: session)
        let threeHours = PreworkoutPlan.Earlier(carbsG: 60, time: session.addingTimeInterval(-3 * 3600))
        let sixHours = PreworkoutPlan.Earlier(carbsG: 60, time: session.addingTimeInterval(-6 * 3600))
        #expect(abs(PreworkoutPlan.credit(earlier: [justAte], session: session) - 60) < 0.001)
        #expect(abs(PreworkoutPlan.credit(earlier: [threeHours], session: session) - 30) < 0.001)
        #expect(abs(PreworkoutPlan.credit(earlier: [sixHours], session: session) - 15) < 0.001)
    }

    @Test func foodEatenAfterTheSessionStartsDoesNotCount() {
        let later = PreworkoutPlan.Earlier(carbsG: 60, time: session.addingTimeInterval(3600))
        #expect(PreworkoutPlan.credit(earlier: [later], session: session) == 0)
    }

    @Test func neededIsTheTargetLessCreditAndWhatIsLogged() {
        #expect(PreworkoutPlan.needed(targetG: 74, creditG: 26, loggedG: 0) == 48)
        #expect(PreworkoutPlan.needed(targetG: 74, creditG: 26, loggedG: 20) == 28)
        #expect(PreworkoutPlan.needed(targetG: 74, creditG: 80, loggedG: 0) == 0)
    }

    @Test func quickCarbsAreTakenFortyFiveMinutesBefore() {
        #expect(PreworkoutPlan.takeTime(session: session) == session.addingTimeInterval(-45 * 60))
    }
}

@Suite struct FlaggedDaysTests {
    @Test func flaggedDaysAreLeftOut() {
        let days = ["2026-10-07", "2026-10-08", "2026-10-09"]
        let kept = FlaggedDays.removing(days, dateOf: { $0 }, flagged: ["2026-10-08"])
        #expect(kept == ["2026-10-07", "2026-10-09"])
    }

    @Test func noFlagsKeepsEverything() {
        let days = ["2026-10-07", "2026-10-08"]
        #expect(FlaggedDays.removing(days, dateOf: { $0 }, flagged: []) == days)
    }

    @Test func anItemWithNoDateIsKept() {
        #expect(FlaggedDays.removing(["x"], dateOf: { _ in nil }, flagged: ["2026-10-08"]) == ["x"])
    }
}

