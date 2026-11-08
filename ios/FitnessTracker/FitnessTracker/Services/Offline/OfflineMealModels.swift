import Foundation
import SwiftData

/// Local mirror of a `meal_entries` row, plus queue bookkeeping - see
/// `OfflineMealQueue`. Reuses `SyncState` from `OfflineWorkoutModels.swift`
/// rather than redefining an identical enum.
@Model
final class QueuedMealEntry {
    @Attribute(.unique) var id: UUID
    var date: String
    /// Account that created this queued record. Optional only for older local stores.
    var ownerId: UUID?
    var mealSlotId: UUID
    var foodId: UUID?
    var recipeId: UUID?
    var quantity: Double
    var loggedAt: Date
    /// Optional, so stores from before it existed open unchanged.
    var eatenAt: Date?
    var syncState: SyncState
    var pendingDeletion: Bool

    init(
        id: UUID,
        date: String,
        ownerId: UUID? = nil,
        mealSlotId: UUID,
        foodId: UUID?,
        recipeId: UUID?,
        quantity: Double,
        loggedAt: Date,
        eatenAt: Date? = nil,
        syncState: SyncState
    ) {
        self.id = id
        self.date = date
        self.ownerId = ownerId
        self.mealSlotId = mealSlotId
        self.foodId = foodId
        self.recipeId = recipeId
        self.quantity = quantity
        self.loggedAt = loggedAt
        self.eatenAt = eatenAt
        self.syncState = syncState
        self.pendingDeletion = false
    }

    func asMealEntry() -> MealEntry {
        MealEntry(id: id, date: date, mealSlotId: mealSlotId, foodId: foodId, recipeId: recipeId, quantity: quantity, loggedAt: loggedAt, eatenAt: eatenAt)
    }
}
