import Foundation

/// Why a day is left out of the calorie calculations.
nonisolated enum DayStatus: String, Codable, CaseIterable, Identifiable {
    case sick
    case notTracked = "not_tracked"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sick: "Sick"
        case .notTracked: "Not tracked"
        }
    }
}

nonisolated struct DayFlag: Codable, Identifiable, Hashable {
    /// ISO date (yyyy-MM-dd) the flag is for.
    let date: String
    let status: DayStatus
    var id: String { date }
}

/// Days the daily check-in reported as off-plan. A check-in on day D says D - 1 was off-plan.
enum OffPlanDays {
    /// The off-plan days themselves (D - 1 for each check-in that reported one).
    static func days(from checkins: [DailyCheckin]) -> Set<String> {
        let calendar = Calendar.current
        var result: Set<String> = []
        for checkin in checkins where checkin.yesterdayOffPlan == true {
            guard let date = DateFormatting.date(fromISODate: checkin.checkinDate),
                  let previous = calendar.date(byAdding: .day, value: -1, to: date) else { continue }
            result.insert(DateFormatting.isoDate(previous))
        }
        return result
    }

    /// The days whose food intake can't be trusted for working out expenditure: the off-plan day
    /// (often under-logged) and the day after it (water and unlogged leftovers).
    static func untrustedIntakeDays(from checkins: [DailyCheckin]) -> Set<String> {
        let calendar = Calendar.current
        var result = days(from: checkins)
        for day in result {
            if let date = DateFormatting.date(fromISODate: day), let next = calendar.date(byAdding: .day, value: 1, to: date) {
                result.insert(DateFormatting.isoDate(next))
            }
        }
        return result
    }
}

/// Leaving flagged days out of a calculation.
nonisolated enum FlaggedDays {
    /// The items whose day isn't flagged.
    static func removing<T>(_ items: [T], dateOf: (T) -> String?, flagged: Set<String>) -> [T] {
        guard !flagged.isEmpty else { return items }
        return items.filter { item in
            guard let date = dateOf(item) else { return true }
            return !flagged.contains(date)
        }
    }
}
