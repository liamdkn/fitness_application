import Foundation
import Supabase

/// The account-lifecycle operations that must cross the backend boundary.
/// Keeping these out of SwiftUI makes the destructive path easier to review
/// and gives the view only data/results to present.
struct AccountDataRepository {
    private let client = SupabaseService.shared.client

    func exportData() async throws -> Data {
        try await client.rpc("export_my_data").execute().data
    }

    func deleteAccount() async throws {
        // Storage objects must be removed while the user still has a valid
        // session. The database function then deletes rows and the auth user.
        try await ProgressPhotoRepository().deleteAllFiles()
        try await RewardRepository().deleteAllFiles()
        try await client.rpc("delete_my_account").execute()

        // `signOut` wipes all account-scoped local caches even when its remote
        // request fails because the server-side user has already been removed.
        try? await SupabaseService.shared.signOut()
    }
}
