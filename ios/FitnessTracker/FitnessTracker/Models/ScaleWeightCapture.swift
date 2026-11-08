import Foundation

struct ScaleWeightCapture: Codable, Identifiable, Hashable {
    let id: UUID
    let ownerId: UUID
    let mealSlotId: UUID
    let grams: Double
    let scaleUnit: Int?
    let date: Date
    let capturedAt: Date

    init(id: UUID = UUID(), ownerId: UUID, mealSlotId: UUID, grams: Double, scaleUnit: Int?, date: Date, capturedAt: Date = Date()) {
        self.id = id
        self.ownerId = ownerId
        self.mealSlotId = mealSlotId
        self.grams = grams
        self.scaleUnit = scaleUnit
        self.date = date
        self.capturedAt = capturedAt
    }
}
