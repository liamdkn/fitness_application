import SwiftUI

/// The day's protein, carbs and fat against their targets, with fibre and
/// sodium - what the main Nutrition screen leaves out to stay light.
struct MacronutrientsView: View {
    let totals: DayMacroTotals
    let proteinTarget: Double?
    let carbsTarget: Double?
    let fatTarget: Double?
    let fibreGoalG: Int
    let sodiumLimitMg: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    MacroProgressCard(label: "Protein", value: totals.proteinG, target: proteinTarget, color: AppColor.protein)
                    MacroProgressCard(label: "Carbs", value: totals.carbsG, target: carbsTarget, color: AppColor.carbs)
                    MacroProgressCard(label: "Fat", value: totals.fatG, target: fatTarget, color: AppColor.fat)
                }
                FibreRow(fibreG: totals.fiberG, goalG: fibreGoalG)
                SodiumRow(sodiumMg: totals.sodiumMg, sodiumLimitMg: sodiumLimitMg)
            }
            .padding()
        }
        .appScreen()
        .navigationTitle("Macronutrients")
        .navigationBarTitleDisplayMode(.inline)
    }
}
