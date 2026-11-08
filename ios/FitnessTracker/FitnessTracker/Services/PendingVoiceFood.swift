import Foundation

struct PendingVoiceFood: Codable, Identifiable {
    let id: UUID
    let ownerId: UUID
    let foodName: String
    let amount: Double
    let unit: String
    let mealSlotId: UUID?
    let mealSlotName: String?
    let candidateFoodIds: [UUID]
    let createdAt: Date

    init(id: UUID = UUID(), ownerId: UUID, foodName: String, amount: Double, unit: String,
         mealSlotId: UUID?, mealSlotName: String?, candidateFoodIds: [UUID], createdAt: Date = Date()) {
        self.id = id
        self.ownerId = ownerId
        self.foodName = foodName
        self.amount = amount
        self.unit = unit
        self.mealSlotId = mealSlotId
        self.mealSlotName = mealSlotName
        self.candidateFoodIds = candidateFoodIds
        self.createdAt = createdAt
    }

    var amountForFoodPicker: Double? {
        switch unit {
        case "grams", "g": amount
        case "millilitres", "ml": amount
        case "servings": amount
        default: nil
        }
    }
}

enum PendingVoiceFoodStore {
    private static let key = "pending-voice-foods-v1"

    static func pending(for ownerId: UUID) -> [PendingVoiceFood] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([PendingVoiceFood].self, from: data) else { return [] }
        return items.filter { $0.ownerId == ownerId }.sorted { $0.createdAt < $1.createdAt }
    }

    static func append(_ item: PendingVoiceFood) {
        guard let data = UserDefaults.standard.data(forKey: key),
              var items = try? JSONDecoder().decode([PendingVoiceFood].self, from: data) else {
            save([item])
            return
        }
        items.removeAll { $0.id == item.id }
        items.append(item)
        save(items)
    }

    static func remove(_ id: UUID) {
        guard let data = UserDefaults.standard.data(forKey: key),
              var items = try? JSONDecoder().decode([PendingVoiceFood].self, from: data) else { return }
        items.removeAll { $0.id == id }
        save(items)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ items: [PendingVoiceFood]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
