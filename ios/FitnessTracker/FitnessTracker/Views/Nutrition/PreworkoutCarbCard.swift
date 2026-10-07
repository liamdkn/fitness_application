import SwiftUI

/// The quick carbs to eat before training: the target less what earlier meals
/// still count for (they fade with the hours before the session) and what's
/// already logged here, with a realistic mix of foods to fill the gap and the
/// time to eat it. Shown on the Preworkout meal only.
struct PreworkoutCarbCard: View {
    let targetG: Double
    /// Carbs already logged in this meal.
    let loggedG: Double
    /// Everything eaten in other meals today, with when.
    let earlier: [PreworkoutPlan.Earlier]
    let date: Date
    /// Session start, as minutes after midnight.
    @Binding var sessionMinutes: Int
    let onLog: (Food, Double) -> Void

    @State private var foodsByKeyword: [String: Food] = [:]

    private var session: Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: sessionMinutes / 60, minute: sessionMinutes % 60, second: 0, of: date) ?? date
    }

    private var credit: Double { PreworkoutPlan.credit(earlier: earlier, session: session) }
    private var counted: Double { credit + loggedG }
    private var needed: Double { PreworkoutPlan.needed(targetG: targetG, creditG: credit, loggedG: loggedG) }
    private var mix: [(food: Food, servings: Double)] { PreworkoutMix.build(neededG: needed, foods: foodsByKeyword) }

    private var sessionBinding: Binding<Date> {
        Binding(
            get: { session },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                sessionMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preworkout carbs")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(counted.rounded())) / \(Int(targetG)) g")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            AppProgressBar(value: min(counted / max(targetG, 1), 1))
                .tint(AppColor.carbs)

            HStack {
                Text("Training at")
                    .font(.subheadline)
                Spacer()
                DatePicker("Training at", selection: sessionBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            if credit >= 0.5 {
                HStack {
                    Text("From earlier meals")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(credit.rounded())) g")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if needed < 1 {
                Label("Target reached", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.success)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Quick carbs")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(needed.rounded())) g at \(PreworkoutPlan.takeTime(session: session).formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                VStack(spacing: 8) {
                    ForEach(mix, id: \.food.id) { item in
                        mixRow(item.food, servings: item.servings)
                    }
                }
                if mix.count > 1 {
                    Button {
                        for item in mix { onLog(item.food, item.servings) }
                    } label: {
                        let total = mix.reduce(0) { $0 + $1.food.carbsG(at: $1.servings) }
                        Label("Log all - \(Int(total.rounded())) g carbs", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimaryCompact)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16)
        .task { await loadFoods() }
    }

    private func mixRow(_ food: Food, servings: Double) -> some View {
        Button {
            onLog(food, servings)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(food.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(food.amountLabel(at: servings))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(food.carbsG(at: servings).rounded())) g carbs")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(AppColor.accent)
            }
        }
        .buttonStyle(.plain)
    }

    /// The first real food with carbs found for each of the mix's keywords.
    private func loadFoods() async {
        let repository = FoodRepository()
        var found: [String: Food] = [:]
        for rule in PreworkoutMix.rules {
            guard let hits = try? await repository.browse(query: rule.keyword, limit: 40) else { continue }
            let first = String(rule.keyword.split(separator: " ")[0])
            if let best = hits.first(where: { !$0.isDrink && !$0.isQuickAdd && $0.carbsG > 0.5 && $0.name.localizedCaseInsensitiveContains(first) }) {
                found[rule.keyword] = best
            }
        }
        foodsByKeyword = found
    }
}
