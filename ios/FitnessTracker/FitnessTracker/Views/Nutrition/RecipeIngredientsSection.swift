import SwiftUI

/// A recipe's ingredients, with the amounts for the portion being logged.
/// Prep recipes keep their ingredients for the whole batch while their macros
/// are per portion, so amounts are scaled by `quantity / portions`.
struct RecipeIngredientList {
    struct Row: Identifiable {
        let food: Food
        let quantity: Double
        var id: UUID { food.id }
    }

    var rows: [Row] = []
    /// Portions in the batch the ingredients make (1 for a plain recipe).
    var portions: Double = 1

    /// Loads the ingredients. `portions` is known when logging from a batch;
    /// otherwise a prep recipe's batch size is looked up.
    static func load(recipe: Recipe, portions knownPortions: Double? = nil) async -> RecipeIngredientList {
        guard let ingredients = try? await RecipeRepository().fetchIngredients(recipeId: recipe.id), !ingredients.isEmpty,
              let foods = try? await FoodRepository().fetchByIds(ingredients.map(\.foodId)) else { return RecipeIngredientList() }
        let foodsById = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var portions = knownPortions ?? 1
        if knownPortions == nil, recipe.isMealPrep,
           let summary = try? await MealPrepRepository().fetchSummaries().first(where: { $0.recipe.id == recipe.id }) {
            portions = max(summary.prep.portions, 1)
        }
        let rows = ingredients.compactMap { ingredient in
            foodsById[ingredient.foodId].map { Row(food: $0, quantity: ingredient.quantity) }
        }
        return RecipeIngredientList(rows: rows, portions: portions)
    }
}

struct RecipeIngredientsSection: View {
    let list: RecipeIngredientList
    /// Portions (servings of the recipe) being logged; the whole recipe's amounts if nil.
    let quantity: Double?

    private var scale: Double { (quantity ?? list.portions) / max(list.portions, 1) }

    var body: some View {
        if !list.rows.isEmpty {
            Section("Ingredients") {
                ForEach(list.rows) { row in
                    LabeledContent(row.food.displayName, value: row.food.amountLabel(at: row.quantity * scale))
                }
            }
            .listRowBackground(AppRowBackground())
        }
    }
}
