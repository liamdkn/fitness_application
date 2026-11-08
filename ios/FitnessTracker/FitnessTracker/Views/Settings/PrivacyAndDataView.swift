import SwiftUI

struct PrivacyAndDataView: View {
    var body: some View {
        Form {
            Section("Information in your account") {
                Text("Fitness Tracker stores the training, nutrition, body measurement, check-in, supplement, and goal information you add so it can show your history and progress.")
                Text("If you add progress or reward photos, they are uploaded to private cloud storage for your account. Progress photos are not included in the data export yet.")
            }
            .listRowBackground(AppRowBackground())

            Section("Apple Health") {
                Text("If you allow access, the app reads steps, sleep, body weight, and workouts to show them alongside your logs. Steps and sleep are synced to your Fitness Tracker account. Health access can be changed or revoked in the Health app.")
            }
            .listRowBackground(AppRowBackground())

            Section("Other services and this device") {
                Text("Account data is stored with Supabase, which provides the app's sign-in, database, and private photo storage. Food barcode lookups may be sent to Open Food Facts to find product information.")
                Text("Offline changes and recently viewed reference data can be kept on this device until they sync or you sign out. Notifications, widgets, and Live Activities display information you choose to track.")
            }
            .listRowBackground(AppRowBackground())

            Section("Your choices") {
                Text("Use Settings → Your Data to export available account data or request permanent account deletion. Deleting your account also removes its uploaded photos. You can sign out to clear account-specific data stored on this device.")
                Text("Nutrition values can be incomplete or user-entered. The app is for fitness tracking and does not provide medical advice.")
            }
            .listRowBackground(AppRowBackground())
        }
        .appScreen()
        .navigationTitle("Privacy & Data Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}
