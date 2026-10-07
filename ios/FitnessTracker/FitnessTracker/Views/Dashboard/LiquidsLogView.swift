import SwiftUI

/// Log anything you drink. Plain water goes in by container or amount; every
/// other drink - a Pepsi, a Monster, a pot of coffee - is a food measured in
/// ml, found by scanning its barcode, searching, or picking one you've saved.
/// A drink is logged as a normal meal entry (into the Drinks slot), so its
/// calories, sugar and sodium count once in the day's totals, and hydration
/// and caffeine are read from the same entries. "Edit" manages the water
/// containers (`WaterContainersEditView`).
struct LiquidsLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var containers: [WaterContainer] = []
    @State private var day = LiquidsDay()
    @State private var quickDrinks: [Food] = []
    @State private var preferences: UserPreferences?
    @State private var customAmountText = ""
    @State private var errorMessage: String?
    @State private var showingEditContainers = false
    @State private var showingDrinkPicker = false
    @State private var showingNewDrink = false
    @State private var showingCoffeeSetup = false
    @State private var showingCustomAmount = false
    @State private var showingMilkAllowance = false
    @State private var pendingDrink: Food?
    private let waterRepository = WaterRepository()
    private let liquidsRepository = LiquidsRepository()
    private let preferencesRepository = UserPreferencesRepository()

    private var halfLife: Double { preferences?.caffeineHalfLifeHours ?? 5 }
    private var caffeineLimit: Int { preferences?.caffeineLimitMg ?? 400 }
    /// What "a glass" means for catch-up advice: a container called glass, or 250 ml.
    private var glassMl: Int { containers.first { $0.name.localizedCaseInsensitiveContains("glass") }?.volumeMl ?? 250 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    waterTiles
                    drinkTiles
                    todayLog

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(AppColor.error)
                    }
                }
                .padding()
            }
            .appScreen()
            .navigationTitle("Liquids")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Edit Containers", systemImage: "pencil") { showingEditContainers = true }
                        Button("New Drink", systemImage: "plus") { showingNewDrink = true }
                        Button("Set Up Coffee", systemImage: "cup.and.saucer") { showingCoffeeSetup = true }
                        Button("Daily Milk Allowance", systemImage: "cup.and.heat.waves") { showingMilkAllowance = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                    .appToolbarTint()
                }
            }
            .navigationDestination(isPresented: $showingMilkAllowance) { MilkAllowanceView() }
            .sensoryFeedback(.success, trigger: day.items.count)
            .task { await load() }
            .alert("Add Water", isPresented: $showingCustomAmount) {
                TextField("ml", text: $customAmountText)
                    .keyboardType(.numberPad)
                Button("Add") { Task { await addCustomWater() } }
                Button("Cancel", role: .cancel) { customAmountText = "" }
            }
            .sheet(isPresented: $showingEditContainers, onDismiss: { Task { await loadContainers() } }) {
                NavigationStack {
                    WaterContainersEditView()
                }
            }
            .sheet(isPresented: $showingDrinkPicker) {
                FoodPickerView(mealSlotName: "Drinks", onLog: { food, quantity in
                    Task { await logDrink(food, quantity: quantity) }
                }, drinksOnly: true)
            }
            .sheet(isPresented: $showingNewDrink) {
                AddCustomFoodView(onCreated: { food in pendingDrink = food }, initialServingUnit: "ml", initialIsDrink: true)
            }
            .sheet(isPresented: $showingCoffeeSetup) {
                CoffeeSetupSheet { food in
                    pendingDrink = food
                    Task { await loadQuickDrinks() }
                }
            }
            .sheet(item: $pendingDrink) { food in
                LogFoodQuantityView(food: food, mealSlotName: LiquidsRepository.slotName) { confirmed, quantity in
                    pendingDrink = nil
                    Task { await logDrink(confirmed, quantity: quantity) }
                }
            }
        }
    }

    // MARK: - Sections

    private var waterTarget: Double { Double(preferences?.dailyWaterMlTargetMin ?? 2000) }

    /// Today's total against the water target, the caffeine so far, and the pace in one line.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(formattedAmount(Int(day.hydrationMl.rounded())))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .rolling(day.hydrationMl)
                Text("of \(formattedAmount(Int(waterTarget)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            AppProgressBar(value: min(day.hydrationMl / max(waterTarget, 1), 1))
                .tint(AppColor.water)
            WaterPaceSection(day: day, preferences: preferences, glassMl: glassMl)

            Divider()
            NavigationLink {
                CaffeineView()
            } label: {
                HStack {
                    Label("Caffeine", systemImage: "cup.and.saucer.fill")
                        .foregroundStyle(AppColor.caffeine)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(day.caffeineMg.rounded())) / \(caffeineLimit) mg")
                            .font(.subheadline.bold())
                            .foregroundStyle(day.caffeineMg > Double(caffeineLimit) ? AppColor.danger : .primary)
                        if day.caffeineMg > 0 {
                            Text("~\(Int(CaffeineModel.level(at: Date(), doses: day.caffeineDoses, halfLifeHours: halfLife).rounded())) mg in you now")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16)
    }

    private let tileColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    /// One tap per container, and an Other tile for any amount.
    private var waterTiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Water").font(.title3.bold())
            LazyVGrid(columns: tileColumns, spacing: 10) {
                ForEach(containers) { container in
                    tile(container.name, "+\(container.volumeMl) ml", icon: "drop.fill") {
                        Task { await addWater(amountMl: container.volumeMl, containerId: container.id) }
                    }
                }
                tile("Other", "any amount", icon: "plus") { showingCustomAmount = true }
            }
        }
    }

    /// Usual drinks as tiles, and one to find any other by scanning or searching.
    private var drinkTiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drinks").font(.title3.bold())
            LazyVGrid(columns: Array(tileColumns.prefix(2)), spacing: 10) {
                ForEach(quickDrinks) { food in
                    tile(food.displayName, detail(for: food), icon: "cup.and.saucer.fill") {
                        pendingDrink = food
                    }
                }
                tile("Add a drink", "scan or search", icon: "barcode.viewfinder") { showingDrinkPicker = true }
            }
        }
    }

    private func tile(_ title: String, _ subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(AppColor.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(12)
            .appCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var todayLog: some View {
        if !day.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today").font(.title3.bold())
                VStack(spacing: 8) {
                    ForEach(day.items) { item in
                        itemRow(item)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard(cornerRadius: 12)
                            .swipeToDelete(cornerRadius: 12) { remove(item) }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: LiquidItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: item))
                Text(item.time.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(item.volumeMl.rounded())) ml").foregroundStyle(.secondary)
                if item.caffeineMg > 0 {
                    Text("\(Int(item.caffeineMg.rounded())) mg caffeine")
                        .font(.caption)
                        .foregroundStyle(AppColor.caffeine)
                }
            }
        }
    }

    // MARK: - Text

    private func title(for item: LiquidItem) -> String {
        switch item.kind {
        case .water(let log):
            return containers.first { $0.id == log.containerId }?.name ?? "Water"
        case .drink(let drink):
            return drink.food.displayName
        }
    }

    private func detail(for food: Food) -> String {
        var parts = ["\(Int(food.calories.rounded())) kcal"]
        if let caffeine = food.caffeineMg, caffeine > 0 { parts.append("\(Int(caffeine.rounded())) mg caffeine") }
        return parts.joined(separator: " \u{00b7} ") + " per \(food.servingLabel)"
    }

    private func formattedAmount(_ ml: Int) -> String {
        ml >= 1000 ? String(format: "%.2f L", Double(ml) / 1000) : "\(ml) ml"
    }

    // MARK: - Loading and actions

    private func load() async {
        await MilkAllowanceService.applyIfNeeded()
        async let prefs = try? preferencesRepository.fetch()
        await loadContainers()
        await loadDay()
        await loadQuickDrinks()
        preferences = await prefs
    }

    private func loadContainers() async {
        do {
            containers = try await waterRepository.fetchContainers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDay() async {
        do {
            day = try await liquidsRepository.fetchDay(date: Date())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadQuickDrinks() async {
        quickDrinks = await liquidsRepository.fetchQuickDrinks()
    }

    private func addWater(amountMl: Int, containerId: UUID?) async {
        do {
            try await waterRepository.addLog(date: Date(), amountMl: amountMl, containerId: containerId)
            errorMessage = nil
            await loadDay()
            await WidgetSnapshotService.shared.refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addCustomWater() async {
        guard let amount = Int(customAmountText), amount > 0 else { return }
        customAmountText = ""
        await addWater(amountMl: amount, containerId: nil)
    }

    private func logDrink(_ food: Food, quantity: Double) async {
        do {
            let slot = try await liquidsRepository.drinksSlot()
            try OfflineMealQueue.shared.addFoodEntry(date: Date(), mealSlotId: slot.id, foodId: food.id, quantity: quantity)
            errorMessage = nil
            await loadDay()
            await loadQuickDrinks()
            await CaffeineReminderService.shared.refresh()
            await WidgetSnapshotService.shared.refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ item: LiquidItem) {
        Task {
            do {
                switch item.kind {
                case .water(let log): try await waterRepository.deleteLog(id: log.id)
                case .drink(let drink): try await OfflineMealQueue.shared.deleteEntry(id: drink.entry.id)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            await loadDay()
            await CaffeineReminderService.shared.refresh()
            await WidgetSnapshotService.shared.refresh(force: true)
        }
    }
}
