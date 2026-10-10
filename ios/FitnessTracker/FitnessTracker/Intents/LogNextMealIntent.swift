import AppIntents

/// Stamps the current time as when the next meal of today was eaten. Meant for an
/// NFC tag: a Shortcuts automation ("when this tag is scanned") runs it, and it
/// works silently in the app's own process, so the meal is stamped straight away.
struct LogNextMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Next Meal"
    static var description = IntentDescription("Records the current time as when you ate your next planned meal today.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await MealStampService.stampNextMeal()
        return .result(dialog: IntentDialog(stringLiteral: MealStampService.message(for: outcome)))
    }
}
