import Foundation

/// Sizing food to a carb target - what the preworkout meal uses to say "this
/// much of that gets you there".
nonisolated enum PreworkoutCarbs {
    /// Carbs to eat before training: `gramsPerKg` of the given bodyweight.
    static func targetG(weightKg: Double?, gramsPerKg: Double) -> Double? {
        guard let weightKg, weightKg > 0, gramsPerKg > 0 else { return nil }
        return (weightKg * gramsPerKg).rounded()
    }

    /// Servings of `food` that supply about `carbsG`, rounded to something
    /// weighable: 5 g or ml for measured foods, half a unit for counted ones
    /// (a banana, a rice cake). Nil if the food has no carbs to speak of.
    static func servings(of food: Food, forCarbsG carbsG: Double) -> Double? {
        guard carbsG > 0, food.carbsG > 0.5, food.servingSize > 0 else { return nil }
        let exact = carbsG / food.carbsG
        let unit = food.servingUnit.lowercased()
        if unit == "g" || unit == "ml" {
            let amount = (exact * food.servingSize / 5).rounded() * 5
            return amount > 0 ? amount / food.servingSize : nil
        }
        let halves = (exact * 2).rounded() / 2
        return halves > 0 ? halves : nil
    }
}

/// How many quick carbs to eat before a session, once the carbs already eaten
/// today are counted, and when to eat them.
nonisolated enum PreworkoutPlan {
    /// Carbs eaten earlier still count towards the target, fading as the hours
    /// pass: half as much for every three hours between eating and training.
    static let halfLifeHours = 3.0
    /// The quick carbs are eaten this long before the session.
    static let leadMinutes = 45

    struct Earlier {
        let carbsG: Double
        let time: Date
    }

    /// Carbs from earlier meals that still count at `session`.
    static func credit(earlier: [Earlier], session: Date) -> Double {
        earlier.reduce(0) { total, meal in
            let hours = session.timeIntervalSince(meal.time) / 3600
            guard hours >= 0 else { return total }
            return total + meal.carbsG * pow(0.5, hours / halfLifeHours)
        }
    }

    /// Quick carbs still to eat: the target less what earlier meals still count
    /// for and what's already logged in the preworkout meal.
    static func needed(targetG: Double, creditG: Double, loggedG: Double) -> Double {
        max(targetG - creditG - loggedG, 0)
    }

    static func takeTime(session: Date) -> Date {
        session.addingTimeInterval(-Double(leadMinutes) * 60)
    }
}

/// A realistic pile of quick carbs for a gap: a base of rice cakes, then dates,
/// a drizzle of honey, and banana to top up - each capped at what you'd
/// actually eat in one go, so it never comes to 100 g of dates.
nonisolated enum PreworkoutMix {
    struct Rule {
        /// Searched for in the food database.
        let keyword: String
        /// The most carbs worth taking from this food in one sitting.
        let maxCarbsG: Double
    }

    /// In the order they're used up. Caps are about 2 rice cakes, 2 dates, a
    /// tablespoon of honey and a banana.
    static let rules = [
        Rule(keyword: "rice cake", maxCarbsG: 15),
        Rule(keyword: "dates", maxCarbsG: 30),
        Rule(keyword: "honey", maxCarbsG: 17),
        Rule(keyword: "banana", maxCarbsG: 27),
    ]

    /// Portions of each food (in the rules' order) adding up to about `neededG`
    /// carbs, stopping when the gap is filled or the caps run out.
    static func build(neededG: Double, foods: [String: Food]) -> [(food: Food, servings: Double)] {
        var remaining = neededG
        var mix: [(food: Food, servings: Double)] = []
        for rule in rules {
            guard remaining >= 2, let food = foods[rule.keyword],
                  let servings = PreworkoutCarbs.servings(of: food, forCarbsG: min(remaining, rule.maxCarbsG)) else { continue }
            mix.append((food, servings))
            remaining -= food.carbsG(at: servings)
        }
        return mix
    }
}
