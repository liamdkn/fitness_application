import SwiftUI

struct PendingVoiceFoodReviewView: View {
    let ownerId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PendingVoiceFood] = []
    @State private var selected: PendingVoiceFood?
    @State private var mealSlots: [MealSlot] = []
    @State private var selectedSlots: [UUID: MealSlot] = [:]
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("There are no voice food entries to review."))
                } else {
                    Section {
                        Text("Siri saved these for you because the food match or amount needs checking.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)

                    ForEach(items) { item in
                        Button { selected = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(AppColor.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.amount.formatted()) \(item.unit) \(item.foodName)")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(item.mealSlotName ?? "Choose meal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppRowBackground())
                        .swipeActions {
                            Button("Discard", role: .destructive) {
                                PendingVoiceFoodStore.remove(item.id)
                                items.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }
            }
            .appScreen()
            .navigationTitle("Review voice foods")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.appToolbarTint()
                }
            }
            .onAppear {
                reload()
                Task { await loadMealSlots() }
            }
            .alert("Couldn't save food", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "The entry is still waiting for review.")
            }
            .sheet(item: $selected) { item in
                if let slot = item.mealSlotId.flatMap({ id in mealSlots.first { $0.id == id } }) ?? selectedSlots[item.id] {
                    FoodPickerView(
                        mealSlotName: slot.name,
                        onLog: { food, quantity in
                            Task { @MainActor in
                                do {
                                    try OfflineMealQueue.shared.addFoodEntry(date: item.createdAt, mealSlotId: slot.id, foodId: food.id, quantity: quantity)
                                    PendingVoiceFoodStore.remove(item.id)
                                    reload()
                                    selectedSlots.removeValue(forKey: item.id)
                                    selected = nil
                                } catch {
                                    saveError = error.localizedDescription
                                }
                            }
                        },
                        initialSearchText: item.foodName,
                        initialAmount: item.amountForFoodPicker,
                        initialAmountUnit: item.unit
                    )
                } else {
                    NavigationStack {
                        Group {
                            if mealSlots.isEmpty {
                                ContentUnavailableView("Meal slots unavailable", systemImage: "fork.knife", description: Text("Connect to the internet and try again. This voice entry is still saved."))
                            } else {
                                List(mealSlots) { slot in
                                    Button(slot.name) { selectedSlots[item.id] = slot }
                                }
                                .scrollContentBackground(.hidden)
                            }
                        }
                        .navigationTitle("Choose a meal")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Cancel") { selected = nil }
                            }
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        items = PendingVoiceFoodStore.pending(for: ownerId)
    }

    @MainActor
    private func loadMealSlots() async {
        mealSlots = (try? await MealSlotsRepository().fetchAll()) ?? []
    }
}
