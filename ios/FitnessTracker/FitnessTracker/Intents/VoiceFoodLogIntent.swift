import AppIntents
import Auth
import Foundation

nonisolated enum VoiceFoodUnit: String, AppEnum {
    case grams
    case millilitres
    case servings

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Amount unit"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .grams: "grams", .millilitres: "millilitres", .servings: "servings"
    ]
}

nonisolated struct VoiceFoodPhrase: AppEntity {
    let id: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food and amount")
    static var defaultQuery = VoiceFoodPhraseQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

nonisolated struct VoiceFoodPhraseQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [VoiceFoodPhrase] {
        identifiers.map(VoiceFoodPhrase.init(id:))
    }

    func entities(matching string: String) async throws -> [VoiceFoodPhrase] {
        guard VoiceFoodContext.parse(string) != nil else { return [] }
        return [VoiceFoodPhrase(id: string)]
    }

    func suggestedEntities() async throws -> [VoiceFoodPhrase] { [] }
}

struct VoiceFoodLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Food by Voice"
    static var description = IntentDescription("Adds a measured food to the current meal, or saves it for you to review if the match is uncertain.")
    static var openAppWhenRun = false
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Food and amount", description: "For example, 12 grams of jalapenos") var foodPhrase: VoiceFoodPhrase

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$foodPhrase)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await performOnMainActor()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    @MainActor
    private func performOnMainActor() async -> String {
        guard let parsed = VoiceFoodContext.parse(foodPhrase.id), parsed.amount <= 10_000 else {
            return "I couldn't read that amount. Try saying, ‘Add 12 grams of jalapenos to Fitness Tracker.’"
        }
        guard let ownerId = SupabaseService.shared.session?.user.id else {
            return "Open Fitness Tracker and sign in before using voice food logging."
        }

        let slots = (try? await MealSlotsRepository().fetchAll()) ?? []
        guard let slot = VoiceMealContext.slot(from: slots, at: Date()) else {
            let item = PendingVoiceFood(ownerId: ownerId, foodName: parsed.foodName, amount: parsed.amount, unit: parsed.unit.rawValue,
                                        mealSlotId: nil, mealSlotName: nil, candidateFoodIds: [])
            PendingVoiceFoodStore.append(item)
            return "Saved for review in Fitness Tracker. I couldn't identify the meal."
        }

        let matches = (try? await FoodRepository().search(query: parsed.foodName, limit: 20)) ?? []
        let exact = matches.filter { VoiceFoodContext.normalized($0.name) == VoiceFoodContext.normalized(parsed.foodName) }
        let confident = exact.count == 1 ? exact[0] : nil

        if let food = confident, food.isVerified, let quantity = VoiceFoodContext.quantity(amount: parsed.amount, unit: parsed.unit, food: food) {
            do {
                try OfflineMealQueue.shared.addFoodEntry(date: Date(), mealSlotId: slot.id, foodId: food.id, quantity: quantity)
                return "Added \(food.name) to \(slot.name)."
            } catch {
                // If the local write cannot be made, preserve the request for review.
            }
        }

        let pending = PendingVoiceFood(
            ownerId: ownerId,
            foodName: parsed.foodName,
            amount: parsed.amount,
            unit: parsed.unit.rawValue,
            mealSlotId: slot.id,
            mealSlotName: slot.name,
            candidateFoodIds: matches.prefix(8).map(\.id)
        )
        PendingVoiceFoodStore.append(pending)
        return "Saved \(parsed.amount.formatted()) \(parsed.unit.rawValue) of \(parsed.foodName) for review in Fitness Tracker."
    }
}

struct FitnessTrackerFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: VoiceFoodLogIntent(),
            phrases: [
                "Add \(\.$foodPhrase) to \(.applicationName)",
                "Log \(\.$foodPhrase) in \(.applicationName)"
            ],
            shortTitle: "Add Food",
            systemImageName: "fork.knife"
        )
    }
}

private enum VoiceMealContext {
    static func slot(from slots: [MealSlot], at date: Date) -> MealSlot? {
        let hour = Calendar.current.component(.hour, from: date)
        let preferred: [String]
        switch hour {
        case 4..<10: preferred = ["breakfast", "morning"]
        case 10..<15: preferred = ["lunch"]
        case 15..<22: preferred = ["dinner", "evening"]
        default: preferred = ["snack"]
        }
        for hint in preferred {
            if let slot = slots.first(where: { $0.name.localizedCaseInsensitiveContains(hint) }) { return slot }
        }
        return slots.first(where: { !$0.isPreworkout })
    }
}

nonisolated private enum VoiceFoodContext {
    struct ParsedFoodAmount {
        let amount: Double
        let unit: VoiceFoodUnit
        let foodName: String
    }

    static func parse(_ value: String) -> ParsedFoodAmount? {
        let pattern = #"^\s*(\d+(?:[.,]\d+)?)\s*(g|grams?|ml|millilit(?:er|re)s?|servings?)\s+(?:of\s+)?(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let amountRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let nameRange = Range(match.range(at: 3), in: value),
              let amount = Double(value[amountRange].replacingOccurrences(of: ",", with: ".")), amount > 0 else { return nil }
        let unitText = value[unitRange].lowercased()
        let unit: VoiceFoodUnit = unitText == "g" || unitText.hasPrefix("gram") ? .grams
            : unitText == "ml" || unitText.hasPrefix("millil") ? .millilitres : .servings
        let name = String(value[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return ParsedFoodAmount(amount: amount, unit: unit, foodName: name)
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    static func quantity(amount: Double, unit: VoiceFoodUnit, food: Food) -> Double? {
        guard food.servingSize > 0 else { return nil }
        switch unit {
        case .grams where food.servingUnit.lowercased() == "g": return amount / food.servingSize
        case .millilitres where food.servingUnit.lowercased() == "ml": return amount / food.servingSize
        case .servings: return amount
        default: return nil
        }
    }
}
