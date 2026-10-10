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
