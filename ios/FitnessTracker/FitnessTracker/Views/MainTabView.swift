import Auth
import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var leftAt: Date?
    @State private var router = MealTagRouter.shared
    @State private var coachRouter = CoachRouter.shared
    @State private var showingVoiceFoodReview = false

    private enum Tab: Hashable { case dashboard, train, nutrition, settings }
    @State private var selectedTab = Tab.dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(Tab.dashboard)
            StartWorkoutView()
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.train)
            MealLogHomeView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                .tag(Tab.nutrition)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        // A meal tag with nothing tracked opens that meal: go to Nutrition for it.
        .onChange(of: router.pendingMealSlotId) { _, id in
            if id != nil { selectedTab = .nutrition }
        }
        // The coach card's buttons: a workout on Train, a day's meals on Nutrition.
        .onChange(of: coachRouter.pending) { _, destination in
            guard let destination else { return }
            selectedTab = destination == .train ? .train : .nutrition
            coachRouter.pending = nil
        }
        .overlay(alignment: .top) { OfflineBanner() }
        .sheet(isPresented: $showingVoiceFoodReview) {
            if let ownerId = SupabaseService.shared.session?.user.id {
                PendingVoiceFoodReviewView(ownerId: ownerId)
            }
        }
        .task {
            refreshVoiceFoodReview()
            await WaterRepository().importWidgetWater()
            await WatchBridge.shared.retryPending()
            await OfflineOutbox.shared.flush()
            await MilkAllowanceService.applyIfNeeded()
            await HealthSyncService.shared.sync()
            await DailyCheckinReminderService.shared.refresh()
            await CaffeineReminderService.shared.refresh()
            await StepReminderService.shared.refresh()
            await WidgetSnapshotService.shared.refresh()
            await SupplementReminderService.shared.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // `.task` only fires once, on this view's first appearance - it
            // won't re-run just from switching back to an already-running
            // app. Re-syncing on every return to foreground means steps and
            // sleep recorded while we were in the background show up without
            // needing a force-quit; for the check-in reminder it's what
            // re-schedules tomorrow's 9am notification once a new day has
            // actually started.
            if newPhase == .background { leftAt = Date() }
            if newPhase == .active, let leftAt, Date().timeIntervalSince(leftAt) > AppIntro.awayThreshold {
                AppIntro.shared.play()
                self.leftAt = nil
            }
            guard newPhase == .active else { return }
            refreshVoiceFoodReview()
            Task {
                await WaterRepository().importWidgetWater()
                await WatchBridge.shared.retryPending()
                await OfflineOutbox.shared.flush()
                await MilkAllowanceService.applyIfNeeded()
                await HealthSyncService.shared.sync()
                await DailyCheckinReminderService.shared.refresh()
                await CaffeineReminderService.shared.refresh()
                await StepReminderService.shared.refresh()
                await WidgetSnapshotService.shared.refresh()
                await SupplementReminderService.shared.refresh()
            }
        }
    }

    private func refreshVoiceFoodReview() {
        guard let ownerId = SupabaseService.shared.session?.user.id else { return }
        showingVoiceFoodReview = !PendingVoiceFoodStore.pending(for: ownerId).isEmpty
    }
}

#Preview {
    MainTabView()
}
