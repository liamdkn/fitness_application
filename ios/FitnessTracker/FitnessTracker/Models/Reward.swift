import Foundation

enum RewardGoalKind: String, Codable, CaseIterable, Identifiable {
    case stars
    case streak
    case perfectWeeks = "perfect_weeks"
    case phaseComplete = "phase_complete"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stars: "Stars this phase"
        case .streak: "Streak"
        case .perfectWeeks: "Perfect weeks"
        case .phaseComplete: "Finish the phase"
        }
    }

    /// "30 stars", "14 days", "3 perfect weeks", "85% of days on plan".
    func targetText(_ value: Int) -> String {
        switch self {
        case .stars: "\(value) stars"
        case .streak: "\(value)-day streak"
        case .perfectWeeks: "\(value) perfect week\(value == 1 ? "" : "s")"
        case .phaseComplete: "\(value)% of days on plan"
        }
    }
}

/// A prize the user sets for themselves: "I'll buy this when I hit that". Behaviour goals only - see
/// docs/streaks-and-rewards-plan.md for why there is no weight-based goal.
struct Reward: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let note: String?
    let photoPath: String?
    let price: Double?
    let link: String?
    let goalKind: RewardGoalKind
    let goalValue: Double
    /// Which phase it belongs to (the phase's `phase_started_at`).
    let phaseStartedAt: String?
    let deadline: String?
    let achievedAt: Date?
    let claimedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, note, price, link, deadline
        case photoPath = "photo_path"
        case goalKind = "goal_kind"
        case goalValue = "goal_value"
        case phaseStartedAt = "phase_started_at"
        case achievedAt = "achieved_at"
        case claimedAt = "claimed_at"
        case createdAt = "created_at"
    }

    var isClaimed: Bool { claimedAt != nil }
}
