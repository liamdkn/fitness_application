import SwiftUI

/// Reads `OrientationLock.shared.mask` for the whole app - the one hook
/// UIKit gives a SwiftUI app to allow rotation on a single screen (Weekly
/// Log's table) while every other screen stays portrait-only.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Also runs when iOS launches the app in the background for new
        // Health data - that's what keeps the step reminders current.
        Task { @MainActor in
            StepReminderService.shared.startObserving()
            // A tap on the supplements Live Activity runs in this process.
            SupplementReminderService.shared.installIntentHandler()
            WatchBridge.shared.activate()
        }
        // UIKit-hosted pieces (alerts, share sheets, the camera scanner) don't
        // see SwiftUI's `.tint`, so give them the accent too.
        UIView.appearance().tintColor = UIColor(AppColor.accent)
        // Nav-bar buttons (Cancel, Done, New Food...) in the normal text colour
        // - white in dark mode - rather than the accent blue.
        UINavigationBar.appearance().tintColor = .label
        UIBarButtonItem.appearance().tintColor = .label
        for state in [UIControl.State.normal, .highlighted, .disabled] {
            UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: UIColor.label], for: state)
        }
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}

@main
struct FitnessTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Shown after a tag opens the app through its link (the Shortcuts route is silent).
    @State private var scanMessage: String?

    var body: some Scene {
        WindowGroup {
            RootView()
                // A tag written with fitnesstracker://meal/next stamps the next meal.
                .onOpenURL { url in
                    guard url.scheme == "fitnesstracker", url.host == "meal", url.path == "/next" else { return }
                    Task {
                        do {
                            scanMessage = MealStampService.message(for: try await MealStampService.stampNextMeal())
                        } catch {
                            scanMessage = error.localizedDescription
                        }
                    }
                }
                .alert("Meal tag", isPresented: Binding(get: { scanMessage != nil }, set: { if !$0 { scanMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(scanMessage ?? "")
                }
                #if DEBUG
                .task { await OfflineQueueSelfTest.runIfRequested() }
                #endif
        }
    }
}
