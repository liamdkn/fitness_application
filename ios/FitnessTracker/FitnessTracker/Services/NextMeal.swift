import Foundation

/// Which meal a tag scan stamps with the time it was eaten.
enum NextMeal {
    /// The first meal, in meal order, with no eaten time yet - empty or not, so a scan
    /// before the food is logged says so instead of jumping ahead. Left out of the order:
    /// Snacks (each snack food keeps a time of its own), the Drinks meal (liquids aren't
    /// a meal), and an empty Preworkout meal (it's only there on training days).
    static func pick(slots: [MealSlot], entries: [MealEntry]) -> MealSlot? {
        slots
            .sorted { $0.sortOrder < $1.sortOrder }
            .first { slot in
                guard !slot.isSnacks,
                      slot.name.caseInsensitiveCompare(LiquidsRepository.slotName) != .orderedSame else { return false }
                let inSlot = entries.filter { $0.mealSlotId == slot.id }
                if inSlot.isEmpty { return !slot.isPreworkout }
                return inSlot.allSatisfy { $0.eatenAt == nil }
            }
    }
}

/// Stamps the current time on the next meal of today - what a scan of the meal tag does.
@MainActor
enum MealStampService {
    enum Outcome {
        case stamped(mealName: String, time: Date)
        /// The next meal has nothing tracked yet, so there's nothing to stamp.
        case nothingTracked(mealName: String)
        /// Every meal already has a time.
        case nothingToStamp
    }

    static func stampNextMeal(now: Date = Date()) async throws -> Outcome {
        let slots = try await MealSlotsRepository().fetchAll()
        let entries = try await OfflineMealQueue.shared.fetchEntries(date: now)
        guard let slot = NextMeal.pick(slots: slots, entries: entries) else { return .nothingToStamp }
        guard entries.contains(where: { $0.mealSlotId == slot.id }) else { return .nothingTracked(mealName: slot.name) }
        for entry in entries where entry.mealSlotId == slot.id {
            _ = try await OfflineMealQueue.shared.updateEatenAt(id: entry.id, eatenAt: now)
        }
        return .stamped(mealName: slot.name, time: now)
    }

    /// What to tell the person after a scan.
    nonisolated static func message(for outcome: Outcome) -> String {
        switch outcome {
        case .stamped(let name, let time):
            "\(name) logged at \(time.formatted(date: .omitted, time: .shortened))"
        case .nothingTracked(let name):
            "You have nothing tracked for \(name) yet. Add what you're eating, then scan again."
        case .nothingToStamp:
            "Every meal already has a time."
        }
    }
}
