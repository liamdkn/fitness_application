import Foundation
import Observation

/// Carries "open this meal" from a tag scan to the Nutrition tab: the scan sets the
/// meal, the tab bar switches to Nutrition, and Nutrition opens that meal on today.
@Observable
@MainActor
final class MealTagRouter {
    static let shared = MealTagRouter()

    var pendingMealSlotId: UUID?

    func open(_ mealSlotId: UUID) {
        pendingMealSlotId = mealSlotId
    }
}
