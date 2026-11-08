import Foundation

@MainActor
enum ScaleWeightCaptureStore {
    private static let key = "scale-weight-captures-v1"

    static func fetch(ownerId: UUID, mealSlotId: UUID, date: Date) -> [ScaleWeightCapture] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rows = try? JSONDecoder().decode([ScaleWeightCapture].self, from: data) else { return [] }
        return rows.filter { $0.ownerId == ownerId && $0.mealSlotId == mealSlotId && Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    static func append(_ capture: ScaleWeightCapture) {
        var rows = allRows()
        rows.append(capture)
        save(rows)
    }

    static func remove(_ id: UUID) {
        save(allRows().filter { $0.id != id })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func allRows() -> [ScaleWeightCapture] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rows = try? JSONDecoder().decode([ScaleWeightCapture].self, from: data) else { return [] }
        return rows
    }

    private static func save(_ rows: [ScaleWeightCapture]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
