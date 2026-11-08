import SwiftUI

private let weekdayNames = [
    1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
    5: "Thursday", 6: "Friday", 7: "Saturday",
]

struct SettingsView: View {
    @ObservedObject private var healthSync = HealthSyncService.shared
    @State private var weeklyCheckinWeekday = 2
    @State private var cardioStepExclusionEnabled = false
    @State private var stepSource: StepSource = .merged
    @State private var stepRemindersEnabled = false
    @State private var stepReminderTime = Date()
    @State private var dailyCheckinRemindersEnabled = false
    @State private var stepRemindersLoaded = false
    @State private var showingUnsentWarning = false
    @State private var unsentChanges = 0
    @State private var preferencesError: String?
    private let preferencesRepository = UserPreferencesRepository()

    var body: some View {
        AppNavigationStack {
            Form {
                Section("Plan") {
                    NavigationLink("My Goals") {
                        MyGoalsView()
                    }
                    NavigationLink("Rewards and Trophy Shelf") {
                        RewardsView()
                    }
                    NavigationLink("Edit Training Split") {
                        RoutineEditorView()
                    }
                    NavigationLink("Gyms") {
                        GymsSettingsView()
                    }
                }
                .listRowBackground(AppRowBackground())

                Section("Progress & health") {
                    NavigationLink("Injuries") {
                        InjuriesView()
                    }
                    NavigationLink("Body Measurements") {
                        MeasurementsView()
                    }
                    healthStatusRow
                    Button("Sync Apple Health") {
                        Task { await healthSync.requestAuthorizationAndSync() }
                    }
                }
                .listRowBackground(AppRowBackground())

                Section("Check-ins") {
                    Picker("Check-In Day", selection: $weeklyCheckinWeekday) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(weekdayNames[weekday] ?? "").tag(weekday)
                        }
                    }
                    .onChange(of: weeklyCheckinWeekday) { _, newValue in
                        Task { await savePreferences(newValue) }
                    }
                    if let preferencesError {
                        Text(preferencesError).foregroundStyle(AppColor.error)
                    }
                    NavigationLink("Check-In History") {
                        WeeklyCheckinHistoryView()
                    }
                    Toggle("Morning weigh-in reminder", isOn: $dailyCheckinRemindersEnabled)
                        .onChange(of: dailyCheckinRemindersEnabled) { _, enabled in
                            guard stepRemindersLoaded else { return }
                            Task { await saveDailyCheckinReminders(enabled) }
                        }
                }
                .listRowBackground(AppRowBackground())

                DisclosureGroup("Activity & reminders") {
                    Toggle("Exclude cardio steps", isOn: $cardioStepExclusionEnabled)
                        .onChange(of: cardioStepExclusionEnabled) { _, newValue in
                            Task { await saveCardioStepExclusion(newValue) }
                        }
                    Text("Subtract steps recorded during logged cardio from the Dashboard total.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Step count", selection: $stepSource) {
                        ForEach(StepSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .onChange(of: stepSource) { _, newValue in
                        Task { await saveStepSource(newValue) }
                    }
                    Text("Merged includes all Health sources. Watch Only uses steps recorded by Apple Watch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Remind me to reach my step goal", isOn: $stepRemindersEnabled)
                    if stepRemindersEnabled {
                        DatePicker("Evening reminder", selection: $stepReminderTime, displayedComponents: .hourAndMinute)
                    }
                    Text("Reminders use your most recent step count from Health, including an earlier nudge when the day is behind.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(AppRowBackground())
                .onChange(of: stepRemindersEnabled) { saveStepReminders() }
                .onChange(of: stepReminderTime) { saveStepReminders() }

                Section("Nutrition") {
                    NavigationLink("Meal Slots") {
                        MealSlotsSettingsView()
                    }
                    NavigationLink("Kitchen Scale") {
                        ScaleSetupView()
                    }
                    NavigationLink("Fibre & Preworkout Targets") {
                        NutritionTargetsView()
                    }
                }
                .listRowBackground(AppRowBackground())

                DisclosureGroup("Experimental") {
                    NavigationLink {
                        LibreOneScanTestView()
                    } label: {
                        Label("Libre 1 NFC test", systemImage: "wave.3.right")
                    }
                    Text("Prototype only. It may not be supported on this iPhone and does not provide glucose readings or alerts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(AppRowBackground())

                Section("Account & privacy") {
                    NavigationLink("Your Data") {
                        AccountDataView()
                    }
                    NavigationLink("Privacy & Data Use") {
                        PrivacyAndDataView()
                    }
                    Button("Sign Out", role: .destructive) {
                        Task {
                            // Send anything waiting first; only warn if some
                            // of it couldn't be (no connection).
                            await LocalData.flushAll()
                            unsentChanges = LocalData.unsentCount
                            if unsentChanges > 0 {
                                showingUnsentWarning = true
                            } else {
                                try? await SupabaseService.shared.signOut()
                            }
                        }
                    }
                    .confirmationDialog(
                        "\(unsentChanges) change\(unsentChanges == 1 ? "" : "s") haven't synced yet. Signing out now will lose them.",
                        isPresented: $showingUnsentWarning,
                        titleVisibility: .visible
                    ) {
                        Button("Sign Out and Discard", role: .destructive) {
                            Task { try? await SupabaseService.shared.signOut() }
                        }
                        Button("Stay Signed In", role: .cancel) {}
                    }
                }
                .listRowBackground(AppRowBackground())
            }
            .appScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadPreferences() }
        }
    }

    @ViewBuilder
    private var healthStatusRow: some View {
        if healthSync.isSyncing {
            Label("Syncing steps & sleep...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } else if let healthError = healthSync.errorMessage {
            Label(healthError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(AppColor.danger)
        } else if let lastSynced = healthSync.lastSyncedAt {
            Label("Synced \(lastSynced, style: .relative) ago", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            Label("Not synced yet", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func loadPreferences() async {
        do {
            let preferences = try await preferencesRepository.fetch()
            weeklyCheckinWeekday = preferences.weeklyCheckinWeekday
            cardioStepExclusionEnabled = preferences.cardioStepExclusionEnabled
            stepSource = preferences.stepSource
            stepRemindersEnabled = preferences.stepRemindersEnabled
            dailyCheckinRemindersEnabled = preferences.dailyCheckinRemindersEnabled
            stepReminderTime = Calendar.current.date(
                bySettingHour: preferences.stepReminderMinutes / 60, minute: preferences.stepReminderMinutes % 60, second: 0, of: Date()
            ) ?? Date()
            // Let the assignments above settle before the onChange handlers
            // start treating changes as the user's own.
            try? await Task.sleep(nanoseconds: 300_000_000)
            stepRemindersLoaded = true
        } catch {
            preferencesError = error.localizedDescription
        }
    }

    private func savePreferences(_ weekday: Int) async {
        do {
            try await preferencesRepository.setWeeklyCheckinWeekday(weekday)
            preferencesError = nil
        } catch {
            preferencesError = error.localizedDescription
        }
    }

    private func saveStepReminders() {
        guard stepRemindersLoaded else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: stepReminderTime)
        let minutes = (parts.hour ?? 18) * 60 + (parts.minute ?? 30)
        let enabled = stepRemindersEnabled
        Task {
            if enabled {
                _ = await NotificationAuthorizationService.requestIfNeeded()
            }
            do {
                try await preferencesRepository.setStepReminders(enabled: enabled, minutes: minutes)
                preferencesError = nil
            } catch {
                preferencesError = error.localizedDescription
            }
            await StepReminderService.shared.refresh(force: true)
        }
    }

    private func saveDailyCheckinReminders(_ enabled: Bool) async {
        if enabled {
            _ = await NotificationAuthorizationService.requestIfNeeded()
        }
        do {
            try await preferencesRepository.setDailyCheckinReminders(enabled: enabled)
            preferencesError = nil
        } catch {
            preferencesError = error.localizedDescription
        }
        await DailyCheckinReminderService.shared.refresh()
    }

    private func saveCardioStepExclusion(_ enabled: Bool) async {
        do {
            try await preferencesRepository.setCardioStepExclusionEnabled(enabled)
            preferencesError = nil
        } catch {
            preferencesError = error.localizedDescription
        }
    }

    private func saveStepSource(_ source: StepSource) async {
        do {
            try await preferencesRepository.setStepSource(source)
            preferencesError = nil
        } catch {
            preferencesError = error.localizedDescription
        }
        await healthSync.requestAuthorizationAndSync()
    }
}
