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

struct UserPreferencesPrivacyDefaultsTests {
    private let legacyJSON = """
    {
      "weekly_checkin_weekday": 2,
      "cardio_step_exclusion_enabled": false,
      "step_source": "merged",
      "enabled_cardio_types": [],
      "preferred_gym_id": null,
      "daily_water_ml_target_min": 2500,
      "daily_water_ml_target_max": 3000
    }
    """

    @Test func legacyPreferencesDoNotOptIntoNotifications() throws {
        let preferences = try JSONDecoder().decode(UserPreferences.self, from: Data(legacyJSON.utf8))
        #expect(!preferences.caffeineRemindersEnabled)
        #expect(!preferences.stepRemindersEnabled)
        #expect(!preferences.dailyCheckinRemindersEnabled)
    }

    @Test func explicitReminderChoicesStillDecode() throws {
        let explicit = legacyJSON.replacingOccurrences(
            of: "\n}",
            with: ",\n  \"caffeine_reminders_enabled\": true,\n  \"step_reminders_enabled\": true,\n  \"daily_checkin_reminders_enabled\": true\n}"
        )
        let preferences = try JSONDecoder().decode(UserPreferences.self, from: Data(explicit.utf8))
        #expect(preferences.caffeineRemindersEnabled)
        #expect(preferences.stepRemindersEnabled)
        #expect(preferences.dailyCheckinRemindersEnabled)
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

@Suite @MainActor struct NextMealTests {
    private let day = "2026-10-10"
    private let breakfast = MealSlot(id: UUID(), name: "Breakfast", sortOrder: 1)
    private let lunch = MealSlot(id: UUID(), name: "Lunch", sortOrder: 2)
    private let snacks = MealSlot(id: UUID(), name: "Snacks", sortOrder: 3)
    private let dinner = MealSlot(id: UUID(), name: "Dinner", sortOrder: 4)

    private func entry(in slot: MealSlot, eaten: Date? = nil) -> MealEntry {
        MealEntry(id: UUID(), date: day, mealSlotId: slot.id, foodId: UUID(), recipeId: nil, quantity: 1, loggedAt: Date(), eatenAt: eaten)
    }

    @Test func theFirstMealWithFoodAndNoTimeIsNext() {
        let slots = [dinner, lunch, breakfast]   // out of order on purpose
        let entries = [entry(in: lunch), entry(in: dinner), entry(in: breakfast)]
        #expect(NextMeal.pick(slots: slots, entries: entries)?.name == "Breakfast")
    }

    @Test func aMealThatAlreadyHasATimeIsSkipped() {
        let entries = [entry(in: breakfast, eaten: Date()), entry(in: lunch), entry(in: dinner)]
        #expect(NextMeal.pick(slots: [breakfast, lunch, dinner], entries: entries)?.name == "Lunch")
    }

    @Test func anEmptyMealIsStillNextSoTheScanCanSayNothingIsTracked() {
        let entries = [entry(in: dinner)]
        #expect(NextMeal.pick(slots: [breakfast, lunch, dinner], entries: entries)?.name == "Breakfast")
    }

    @Test func snacksDrinksAndAnEmptyPreworkoutAreNotInTheOrder() {
        let preworkout = MealSlot(id: UUID(), name: "Preworkout", sortOrder: 0)
        let drinks = MealSlot(id: UUID(), name: "Drinks", sortOrder: 0)
        let entries = [entry(in: snacks), entry(in: drinks), entry(in: breakfast, eaten: Date()), entry(in: lunch, eaten: Date())]
        #expect(NextMeal.pick(slots: [preworkout, drinks, breakfast, lunch, snacks, dinner], entries: entries)?.name == "Dinner")
    }

    @Test func aPreworkoutMealWithFoodCountsLikeAnyOther() {
        let preworkout = MealSlot(id: UUID(), name: "Preworkout", sortOrder: 0)
        let entries = [entry(in: preworkout)]
        #expect(NextMeal.pick(slots: [preworkout, breakfast], entries: entries)?.name == "Preworkout")
    }

    @Test func nothingIsNextWhenEveryMealHasATime() {
        let entries = [entry(in: breakfast, eaten: Date()), entry(in: lunch, eaten: Date())]
        #expect(NextMeal.pick(slots: [breakfast, lunch], entries: entries) == nil)
    }
}

@Suite struct FoodDetailTests {
    private func food(_ extra: String = "", source: String = "seed", isVerified: Bool = false, sourceFoodId: String? = nil) throws -> Food {
        let id = "00000000-0000-0000-0000-000000000001"
        let json = """
        {"id":"\(id)","name":"Banana","brand":null,"serving_size":118,"serving_unit":"g","calories":105,
         "protein_g":1.3,"carbs_g":27,"fat_g":0.4,"fiber_g":3.1,"barcode":null,"source":"\(source)",
         "is_custom":false,"created_by":null,"is_verified":\(isVerified),"sodium_mg":null,"caffeine_mg":null,
         "source_food_id":\(sourceFoodId.map { "\"\($0)\"" } ?? "null")\(extra)}
        """
        return try JSONDecoder().decode(Food.self, from: Data(json.utf8))
    }

    @Test func detailFieldsDecodeWhenPresentAndAreNilWhenAbsent() throws {
        let plain = try food()
        #expect(plain.sugarG == nil && plain.saturatedFatG == nil && plain.cholesterolMg == nil && plain.potassiumMg == nil)
        let detailed = try food(#","sugar_g":14.4,"saturated_fat_g":0.1,"cholesterol_mg":0,"potassium_mg":422"#)
        #expect(detailed.sugarG == 14.4)
        #expect(detailed.sugarG(at: 2) == 28.8)
        #expect(detailed.cholesterolMg == 0)
        #expect(detailed.potassiumMg == 422)
    }

    @Test func provenanceSaysWhereTheNumbersCameFrom() throws {
        #expect(try food(source: "seed").provenanceLabel == "Built-in")
        #expect(try food(source: "off").provenanceLabel == "Community \u{00b7} Open Food Facts")
        #expect(try food(source: "nutritionix", isVerified: true).provenanceLabel == "Verified \u{00b7} Nutritionix")
        #expect(try food(source: "nutritionix", isVerified: false).provenanceLabel == "Nutritionix")
        #expect(try food(source: "user").provenanceLabel == "Your entry")
        #expect(try food(source: "ocr").provenanceLabel == "Your entry")
        #expect(try food(source: "user", sourceFoodId: "00000000-0000-0000-0000-000000000002").provenanceLabel == "Your correction")
    }
}

@Suite struct RunTotalDistanceTests {
    private func run(distance: Double?, warmupKm: Double? = nil, cooldownKm: Double? = nil, warmupMin: Int? = nil) throws -> PlannedRun {
        func number(_ value: Double?) -> String { value.map { "\($0)" } ?? "null" }
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","running_plan_id":"00000000-0000-0000-0000-000000000002",
         "date":"2026-10-14","run_type":"easy","target_distance_km":\(number(distance)),"target_duration_min":null,
         "notes":null,"warmup_km":\(number(warmupKm)),"cooldown_km":\(number(cooldownKm)),
         "warmup_min":\(warmupMin.map(String.init) ?? "null")}
        """
        return try JSONDecoder().decode(PlannedRun.self, from: Data(json.utf8))
    }

    @Test func warmUpAndCoolDownComeOutOfTheTotal() throws {
        let planned = try run(distance: 9, warmupKm: 1.5, cooldownKm: 1)
        #expect(planned.mainDistanceKm == 6.5)
    }

    @Test func noWarmUpMeansTheWholeTotalIsMain() throws {
        #expect(try run(distance: 8).mainDistanceKm == 8)
    }

    @Test func aWarmUpSetByTimeDoesNotReduceADistance() throws {
        #expect(try run(distance: 8, warmupMin: 10).mainDistanceKm == 8)
    }

    @Test func theMainPartNeverGoesNegative() throws {
        #expect(try run(distance: 2, warmupKm: 1.5, cooldownKm: 1.5).mainDistanceKm == 0)
    }

    @Test func noTotalMeansNoMainDistance() throws {
        #expect(try run(distance: nil, warmupKm: 1).mainDistanceKm == nil)
    }
}

@Suite @MainActor struct RunFeedbackTests {
    private func result(_ type: RunType = .easy, target: Double? = 5, actual: Double? = 5, effort: Int? = nil,
                        heartRate: Int? = nil, baseline: Double? = nil, targetPace: Double? = nil, actualPace: Double? = nil) -> RunFeedback.Result {
        RunFeedback.Result(runType: type, targetKm: target, actualKm: actual, effort: effort, avgHeartRate: heartRate,
                           heartRateBaseline: baseline, targetPaceSec: targetPace, actualPaceSec: actualPace)
    }

    @Test func aCleanWeekProgresses() {
        let verdict = RunFeedback.verdict(for: [result(.easy, target: 5, actual: 5.1, effort: 4), result(.long, target: 12, actual: 12.2, effort: 6)])
        #expect(verdict?.call == .progress)
    }

    @Test func aWeekWithNothingToJudgeHasNoVerdict() {
        #expect(RunFeedback.verdict(for: []) == nil)
        #expect(RunFeedback.verdict(for: [result(target: nil, actual: 5)]) == nil)
    }

    @Test func oneShortRunHoldsAndTwoBackOff() {
        let one = RunFeedback.verdict(for: [result(target: 5, actual: 5), result(target: 10, actual: 8)])
        #expect(one?.call == .hold)
        let two = RunFeedback.verdict(for: [result(target: 5, actual: nil), result(target: 10, actual: 8)])
        #expect(two?.call == .backOff)
    }

    @Test func aHardEasyRunBlocksProgressButIsNotAlarming() {
        let verdict = RunFeedback.verdict(for: [result(.easy, effort: 8), result(.long, target: 12, actual: 12)])
        #expect(verdict?.call == .hold)
    }

    @Test func aTenOutOfTenBacksOff() {
        #expect(RunFeedback.verdict(for: [result(.long, target: 12, actual: 12, effort: 10)])?.call == .backOff)
    }

    @Test func aMuchSlowerLongRunBacksOff() {
        let verdict = RunFeedback.verdict(for: [result(.long, target: 12, actual: 12, targetPace: 360, actualPace: 420)])
        #expect(verdict?.call == .backOff)
    }

    @Test func heartRateWellAboveTheBaselineHolds() {
        let verdict = RunFeedback.verdict(for: [result(.easy, effort: 4, heartRate: 160, baseline: 140)])
        #expect(verdict?.call == .hold)
    }

    private func planned(_ type: RunType, km: Double, date: String, warmup: Double? = nil, cooldown: Double? = nil) throws -> PlannedRun {
        let json = """
        {"id":"\(UUID().uuidString)","running_plan_id":"00000000-0000-0000-0000-000000000002","date":"\(date)",
         "run_type":"\(type.rawValue)","target_distance_km":\(km),"target_duration_min":null,"notes":null,
         "warmup_km":\(warmup.map { "\($0)" } ?? "null"),"cooldown_km":\(cooldown.map { "\($0)" } ?? "null")}
        """
        return try JSONDecoder().decode(PlannedRun.self, from: Data(json.utf8))
    }

    @Test func holdRepeatsTheLongRunInsteadOfSteppingUp() throws {
        let last = [try planned(.long, km: 14, date: "2026-10-10")]
        let next = [try planned(.long, km: 15, date: "2026-10-17")]
        let suggestion = RunFeedback.suggestion(for: .init(call: .hold, reasons: ["x"]), thisWeek: last, upcoming: next, weekNumber: 6)
        #expect(suggestion?.changes.first?.toKm == 14)
        #expect(suggestion?.changes.first?.fromKm == 15)
    }

    @Test func holdSaysNothingWhenThePlanAlreadyRepeats() throws {
        let last = [try planned(.long, km: 14, date: "2026-10-10")]
        let next = [try planned(.long, km: 14, date: "2026-10-17")]
        #expect(RunFeedback.suggestion(for: .init(call: .hold, reasons: ["x"]), thisWeek: last, upcoming: next, weekNumber: 6) == nil)
    }

    @Test func progressIsAGoAheadWithNothingToApply() throws {
        let last = [try planned(.long, km: 14, date: "2026-10-10")]
        let next = [try planned(.long, km: 15, date: "2026-10-17")]
        let suggestion = RunFeedback.suggestion(for: .init(call: .progress, reasons: ["x"]), thisWeek: last, upcoming: next, weekNumber: 6)
        #expect(suggestion != nil)
        #expect(suggestion?.changes.isEmpty == true)
    }

    @Test func backOffTakesAbout15PercentOffEachRemainingRun() throws {
        let next = [try planned(.easy, km: 6, date: "2026-10-14"), try planned(.long, km: 16, date: "2026-10-17")]
        let suggestion = RunFeedback.suggestion(for: .init(call: .backOff, reasons: ["x"]), thisWeek: [], upcoming: next, weekNumber: 6)
        #expect(suggestion?.changes.map(\.toKm) == [5, 13.5])
    }

    @Test func backOffKeepsRoomForTheWarmUpAndCoolDown() throws {
        let next = [try planned(.easy, km: 3, date: "2026-10-14", warmup: 1, cooldown: 1)]
        let suggestion = RunFeedback.suggestion(for: .init(call: .backOff, reasons: ["x"]), thisWeek: [], upcoming: next, weekNumber: 6)
        // 3 km less 15% rounds to 2.5, which already leaves 0.5 km of main running.
        #expect(suggestion?.changes.first?.toKm == 2.5)
    }
}

@Suite @MainActor struct OffPlanExclusionTests {
    private func checkin(_ date: String, offPlan: Bool) throws -> DailyCheckin {
        let json = """
        {"id":"\(UUID().uuidString)","checkin_date":"\(date)","weight_kg":null,"routine_day_id":null,"workout_choice_label":null,
         "is_rest_day":false,"energy_level":null,"soreness_level":null,"yesterday_water_ml":null,
         "yesterday_off_plan":\(offPlan),"yesterday_off_plan_notes":null}
        """
        return try JSONDecoder().decode(DailyCheckin.self, from: Data(json.utf8))
    }

    @Test func aCheckinOnDFlagsTheDayBefore() throws {
        let days = OffPlanDays.days(from: [try checkin("2026-10-10", offPlan: true), try checkin("2026-10-11", offPlan: false)])
        #expect(days == ["2026-10-09"])
    }

    @Test func theOffPlanDayAndTheDayAfterAreUntrusted() throws {
        let days = OffPlanDays.untrustedIntakeDays(from: [try checkin("2026-10-10", offPlan: true)])
        #expect(days == ["2026-10-09", "2026-10-10"])
    }

    @Test func aQuarterOfTheWindowIsTheLimit() {
        #expect(!AdaptiveTDEEEngine.tooMuchExcluded(days: 5, windowDays: 21))
        #expect(AdaptiveTDEEEngine.tooMuchExcluded(days: 6, windowDays: 21))
        #expect(!AdaptiveTDEEEngine.tooMuchExcluded(days: 0, windowDays: 21))
    }
}

@Suite @MainActor struct PhaseReportCalculatorTests {
    private func date(_ iso: String) -> Date { DateFormatting.date(fromISODate: iso)! }

    private func goal(from effective: String, phaseStart: String = "2026-09-01", calories: Double = 2000, rate: Double? = -0.5,
                      type: GoalPhaseType = .cut, weeks: Int = 12) -> UserGoal {
        UserGoal(id: UUID(), effectiveFrom: effective, phaseStartedAt: phaseStart, phaseType: type, startingWeightKg: 80,
                 durationWeeks: weeks, dailyCalorieTarget: calories, proteinGTarget: 160, carbsGTarget: nil, fatGTarget: nil,
                 targetWeightKg: nil, weeklyWeightChangeKg: rate, stepTarget: 9000, sleepTargetMinutes: nil,
                 cardioSessionsPerWeek: 2, cardioMinutesPerSession: 30, strengthSessionsPerWeek: 4, strengthOptionalSessions: 1)
    }

    private func checkin(_ day: String, offPlan: Bool) throws -> DailyCheckin {
        let json = """
        {"id":"\(UUID().uuidString)","checkin_date":"\(day)","weight_kg":null,"routine_day_id":null,"workout_choice_label":null,
         "is_rest_day":false,"energy_level":null,"soreness_level":null,"yesterday_water_ml":null,
         "yesterday_off_plan":\(offPlan),"yesterday_off_plan_notes":null}
        """
        return try JSONDecoder().decode(DailyCheckin.self, from: Data(json.utf8))
    }

    private func weight(_ day: String, _ kg: Double) -> BodyWeightLog {
        BodyWeightLog(id: UUID(), loggedAt: date(day).addingTimeInterval(8 * 3600), weightKg: kg, source: "manual")
    }

    private func isoDay(_ start: String, plus offset: Int) -> String {
        DateFormatting.isoDate(Calendar.current.date(byAdding: .day, value: offset, to: date(start))!)
    }

    @Test func offPlanSurplusUsesTheTargetInForceEachDay() throws {
        // Target 2,000 until 6 Sep, then 1,900. Off-plan: 3 Sep (3,000 kcal), 6 Sep (2,700), 8 Sep (nothing logged).
        var input = PhaseReportInput(goals: [goal(from: "2026-09-01"), goal(from: "2026-09-06", calories: 1900)],
                                     asOf: date("2026-09-10"))
        input.checkins = [try checkin("2026-09-04", offPlan: true), try checkin("2026-09-07", offPlan: true), try checkin("2026-09-09", offPlan: true)]
        for offset in 0..<9 {
            let day = isoDay("2026-09-01", plus: offset)
            if day == "2026-09-08" { continue }
            input.dailyCalories[day] = day == "2026-09-03" ? 3000 : (day == "2026-09-06" ? 2700 : 1900)
        }
        let offPlan = try #require(PhaseReportCalculator(input).report()?.offPlan)
        #expect(offPlan.offPlanDays == 3)
        #expect(offPlan.offPlanDaysWithoutCalories == 1)
        #expect(offPlan.loggedSurplusKcal == 1800)   // (3000 - 2000) + (2700 - 1900)
        // A 0.5 kg/week plan is a 550 kcal/day deficit.
        #expect(abs((offPlan.daysOfDeficitCancelled ?? 0) - 1800.0 / 550) < 0.001)
    }

    @Test func consecutiveOffPlanDaysFormRuns() throws {
        // Off-plan on the 5th, 6th, 7th, 9th, 10th, 11th and 12th: a run of 3 and a run of 4.
        var input = PhaseReportInput(goals: [goal(from: "2026-09-01")], asOf: date("2026-09-20"))
        input.checkins = try [6, 7, 8, 10, 11, 12, 13].map { try checkin("2026-09-\(String(format: "%02d", $0))", offPlan: true) }
        let offPlan = try #require(PhaseReportCalculator(input).report()?.offPlan)
        #expect(offPlan.offPlanDays == 7)
        #expect(offPlan.runCount == 2)
        #expect(offPlan.longestRun == 4)
    }

    @Test func sickAndUntrackedDaysAreCountedApart() throws {
        var input = PhaseReportInput(goals: [goal(from: "2026-09-01")], asOf: date("2026-09-05"))
        input.dayFlags = [DayFlag(date: "2026-09-02", status: .sick), DayFlag(date: "2026-09-03", status: .notTracked)]
        input.dailyCalories = ["2026-09-01": 2000, "2026-09-02": 900, "2026-09-03": 1200]   // 4th has nothing at all
        let offPlan = try #require(PhaseReportCalculator(input).report()?.offPlan)
        #expect(offPlan.sickDays == 1)
        #expect(offPlan.notTrackedDays == 2)   // the flagged day and the empty one
        #expect(offPlan.onPlanDays == 1)
    }

    @Test func aSickDaysWeighInStaysOutOfTheRate() throws {
        let days = (0..<28).map { isoDay("2026-09-01", plus: $0) }
        let clean = days.enumerated().map { weight($0.element, 80 - Double($0.offset) * 0.07) }
        var dipped = clean
        dipped[24] = weight(days[24], clean[24].weightKg - 5)   // a dehydrated low, near the end where it pulls hardest
        var flagged = PhaseReportInput(goals: [goal(from: "2026-09-01")], asOf: date("2026-09-29"))
        flagged.weights = dipped
        flagged.dayFlags = [DayFlag(date: days[24], status: .sick)]
        var unflagged = flagged
        unflagged.dayFlags = []
        var reference = flagged
        reference.weights = clean
        reference.dayFlags = []

        let rateFlagged = try #require(PhaseReportCalculator(flagged).report()?.progress.actualRatePerWeek)
        let rateUnflagged = try #require(PhaseReportCalculator(unflagged).report()?.progress.actualRatePerWeek)
        let rateClean = try #require(PhaseReportCalculator(reference).report()?.progress.actualRatePerWeek)
        #expect(abs(rateFlagged - rateClean) < 0.05)
        #expect(abs(rateUnflagged - rateClean) > 0.05)
        let dot = try #require(PhaseReportCalculator(flagged).report()?.progress.dots.first { DateFormatting.isoDate($0.date) == days[24] })
        #expect(dot.isSick)
    }

    @Test func theProjectionNeedsTwoWeeksOfWeighInsAndAWeekLeft() throws {
        var input = PhaseReportInput(goals: [goal(from: "2026-09-01")], asOf: date("2026-09-14"))
        input.weights = (0..<13).map { weight(isoDay("2026-09-01", plus: $0), 80 - Double($0) * 0.07) }
        #expect(PhaseReportCalculator(input).report()?.projection == nil)
        input.weights.append(weight("2026-09-14", 79.0))
        input.asOf = date("2026-09-15")
        #expect(PhaseReportCalculator(input).report()?.projection != nil)
        // Under a week left: hidden again.
        input.asOf = date("2026-11-24")   // the phase ends 24 Nov (12 weeks from 1 Sep)... three days short of it
        input.asOf = date("2026-11-21")
        #expect(PhaseReportCalculator(input).report()?.projection == nil)
    }

    @Test func plannedTreatsRaiseTheOnPlanProjection() throws {
        var input = PhaseReportInput(goals: [goal(from: "2026-09-01")], asOf: date("2026-09-20"))
        input.weights = (0..<20).map { weight(isoDay("2026-09-01", plus: $0), 80 - Double($0) * 0.07) }
        let without = try #require(PhaseReportCalculator(input).report()?.projection)
        input.plannedTreats = [PlannedTreat(id: UUID(), date: "2026-10-01", mealSlotId: nil, label: "Birthday",
                                            extraCalories: 3850, extraProteinG: 0, extraCarbsG: 0, extraFatG: 0)]
        let with = try #require(PhaseReportCalculator(input).report()?.projection)
        // 3,850 kcal is half a kilo; it moves the on-plan end of the range (and only that end).
        #expect(abs((with.highKg - without.highKg) - 0.5) < 0.0001 || abs((with.lowKg - without.lowKg) - 0.5) < 0.0001)
    }

    private func liftInput(sessions: [(day: String, sets: [(Double, Int, Bool)])], sick: [String] = []) -> (PhaseReportInput, UUID) {
        let exercise = UUID()
        var input = PhaseReportInput(goals: [goal(from: "2026-09-01")], asOf: date("2026-10-30"))
        input.exerciseNames = [exercise: "Bench"]
        for session in sessions {
            let id = UUID()
            input.workouts.append(.init(id: id, date: date(session.day)))
            for set in session.sets {
                input.sets.append(.init(workoutId: id, exerciseId: exercise, reps: set.1, weightKg: set.0, isWarmup: set.2))
            }
        }
        input.dayFlags = sick.map { DayFlag(date: $0, status: .sick) }
        return (input, exercise)
    }

    @Test func liftsIgnoreWarmUpsAndNeedThreeSessions() throws {
        let (input, _) = liftInput(sessions: [
            ("2026-09-03", [(60, 8, false), (200, 5, true)]),   // a heavy "warm-up" must not count
            ("2026-09-10", [(62.5, 8, false)]),
            ("2026-09-17", [(65, 8, false)]),
        ])
        let lifts = try #require(PhaseReportCalculator(input).report()?.lifts)
        let bench = try #require(lifts.topUp.first)
        // 60 x 8 -> 60 * (1 + 8/30) = 76; the 200 kg warm-up would have made this 233.
        #expect(abs(bench.firstE1RM - 76) < 0.001)
        #expect(lifts.exercisesUp == 1)

        let (twoSessions, _) = liftInput(sessions: [("2026-09-03", [(60, 8, false)]), ("2026-09-10", [(65, 8, false)])])
        #expect(PhaseReportCalculator(twoSessions).report()?.lifts == nil)
    }

    @Test func aDropAfterABreakIsAnnotated() throws {
        // Last two sessions 14 days apart.
        let (gap, _) = liftInput(sessions: [("2026-09-03", [(70, 8, false)]), ("2026-09-10", [(70, 8, false)]),
                                            ("2026-09-17", [(70, 8, false)]), ("2026-10-01", [(60, 8, false)])])
        let drop = try #require(PhaseReportCalculator(gap).report()?.lifts?.topDown.first)
        #expect(drop.afterBreak)

        // Last two sessions a week apart, but sick in between.
        let (sick, _) = liftInput(sessions: [("2026-09-03", [(70, 8, false)]), ("2026-09-10", [(70, 8, false)]),
                                             ("2026-09-17", [(70, 8, false)]), ("2026-09-24", [(60, 8, false)])],
                                  sick: ["2026-09-20"])
        #expect(try #require(PhaseReportCalculator(sick).report()?.lifts?.topDown.first).afterBreak)

        // Same drop, no gap and no illness: not annotated.
        let (plain, _) = liftInput(sessions: [("2026-09-03", [(70, 8, false)]), ("2026-09-10", [(70, 8, false)]),
                                              ("2026-09-17", [(70, 8, false)]), ("2026-09-24", [(60, 8, false)])])
        #expect(try #require(PhaseReportCalculator(plain).report()?.lifts?.topDown.first).afterBreak == false)
    }
}

