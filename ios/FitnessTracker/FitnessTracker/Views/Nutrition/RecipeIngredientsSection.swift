import SwiftUI

/// A recipe's ingredients as it was made - the whole batch's amounts, not scaled
/// to the portion being eaten - so you can see what's in it.
struct RecipeIngredientList {
    struct Row: Identifiable {
        let food: Food
        let quantity: Double
        var id: UUID { food.id }
    }

    var rows: [Row] = []

    static func load(recipe: Recipe) async -> RecipeIngredientList {
        guard let ingredients = try? await RecipeRepository().fetchIngredients(recipeId: recipe.id), !ingredients.isEmpty,
              let foods = try? await FoodRepository().fetchByIds(ingredients.map(\.foodId)) else { return RecipeIngredientList() }
        let foodsById = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return RecipeIngredientList(rows: ingredients.compactMap { ingredient in
            foodsById[ingredient.foodId].map { Row(food: $0, quantity: ingredient.quantity) }
        })
    }
}

struct RecipeIngredientsSection: View {
    let list: RecipeIngredientList

    var body: some View {
        if !list.rows.isEmpty {
            Section("Ingredients") {
                ForEach(list.rows) { row in
                    LabeledContent(row.food.displayName, value: row.food.amountLabel(at: row.quantity))
                }
            }
            .listRowBackground(AppRowBackground())
        }
    }
}
