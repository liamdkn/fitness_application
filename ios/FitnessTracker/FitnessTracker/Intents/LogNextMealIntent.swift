import AppIntents

/// Stamps the current time as when the next meal of today was eaten. Meant for an
/// NFC tag: a Shortcuts automation ("when this tag is scanned") runs it, and it
/// works silently in the app's own process, so the meal is stamped straight away.
struct LogNextMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Next Meal"
    static var description = IntentDescription("Records the current time as when you ate your next planned meal today.")
    /// Runs quietly in the background, and only comes to the front when the next meal has
    /// nothing in it: then the app opens on that meal so it can be filled in.
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await MealStampService.stampNextMeal()
        let dialog = IntentDialog(stringLiteral: MealStampService.message(for: outcome))
        if case .nothingTracked(_, let mealSlotId) = outcome {
            await MealTagRouter.shared.open(mealSlotId)
            try await continueInForeground(dialog, alwaysConfirm: false)
        }
        return .result(dialog: dialog)
    }
}
