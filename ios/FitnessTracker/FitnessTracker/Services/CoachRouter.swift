import Foundation
import Observation

/// Carries "go here" from the coach card to the tab bar: Train for a workout, Nutrition for a
/// day's meals. The tab bar switches tabs; Nutrition opens on the date.
@Observable
@MainActor
final class CoachRouter {
    static let shared = CoachRouter()

    enum Destination: Equatable { case train, nutrition }

    var pending: Destination?
    /// The day Nutrition should open on (read once, then cleared).
    var nutritionDate: Date?

    func openTrain() { pending = .train }

    func openNutrition(daysFromToday: Int) {
        let today = Calendar.current.startOfDay(for: Date())
        nutritionDate = Calendar.current.date(byAdding: .day, value: daysFromToday, to: today)
        pending = .nutrition
    }
}
