import Foundation

struct MealSlot: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int

    /// The slot eaten before training. Slots are the user's own rows, so it's
    /// recognised by name ("Preworkout", "Pre-workout", "Pre workout").
    var isPreworkout: Bool {
        let squashed = name.lowercased().filter { $0.isLetter }
        return squashed.hasPrefix("preworkout")
    }

    /// Snacks are eaten throughout the day, so each keeps its own time rather
    /// than sharing one for the meal. Recognised by name, like the preworkout slot.
    var isSnacks: Bool { name.localizedCaseInsensitiveContains("snack") }

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
    }
}
