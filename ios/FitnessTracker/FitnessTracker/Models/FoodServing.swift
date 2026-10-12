import Foundation

/// A named way to measure a food by count ("1 medium", "1 large egg"), worth a fixed
/// number of grams. Picking one just resolves to a gram amount, so nothing that works
/// from grams has to know these exist.
struct FoodServing: Codable, Identifiable, Hashable {
    let id: UUID
    let foodId: UUID
    let label: String
    let grams: Double
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, label, grams
        case foodId = "food_id"
        case sortOrder = "sort_order"
    }
}
