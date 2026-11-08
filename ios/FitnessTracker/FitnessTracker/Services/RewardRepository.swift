import Foundation
import Supabase

struct RewardRepository {
    let client = SupabaseService.shared.client
    private let bucket = "reward-photos"

    private struct NewReward: Encodable {
        let user_id: UUID
        let title: String
        let photo_path: String?
        let price: Double?
        let link: String?
        let goal_kind: String
        let goal_value: Double
        let phase_started_at: String?
        let deadline: String?
    }

    /// Every reward, newest first.
    func fetchAll() async throws -> [Reward] {
        try await client
            .from("rewards")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Uploads the photo first (if any), then records the row, so a row never points at a
    /// missing file.
    @discardableResult
    func create(
        title: String, photo: Data?, price: Double?, link: String?,
        goalKind: RewardGoalKind, goalValue: Double, phaseStartedAt: String?, deadline: Date?
    ) async throws -> Reward {
        let userId = try await client.auth.session.user.id
        var photoPath: String?
        if let photo {
            let path = "\(userId)/\(UUID().uuidString).jpg"
            try await client.storage.from(bucket).upload(path, data: photo, options: FileOptions(contentType: "image/jpeg"))
            photoPath = path
        }
        let inserted: [Reward] = try await client
            .from("rewards")
            .insert(NewReward(
                user_id: userId, title: title, photo_path: photoPath, price: price, link: link,
                goal_kind: goalKind.rawValue, goal_value: goalValue, phase_started_at: phaseStartedAt,
                deadline: deadline.map(DateFormatting.isoDate)
            ))
            .select()
            .execute()
            .value
        guard let reward = inserted.first else { throw RepositoryError.insertFailed }
        return reward
    }

    private struct AchievedUpdate: Encodable { let achieved_at: String }
    private struct ClaimedUpdate: Encodable { let claimed_at: String }

    /// Marks a reward earned. Only ever sets it once, so an achievement can't be undone.
    func markAchieved(id: UUID) async throws {
        try await client
            .from("rewards")
            .update(AchievedUpdate(achieved_at: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: id)
            .is("achieved_at", value: nil)
            .execute()
    }

    func markClaimed(id: UUID) async throws {
        try await client
            .from("rewards")
            .update(ClaimedUpdate(claimed_at: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: id)
            .execute()
    }

    /// A missed deadline just clears: the reward rolls on with no failure screen. An explicit null,
    /// since the synthesized encoder would leave the key out and the column would keep its value.
    func clearDeadline(id: UUID) async throws {
        struct Clear: Encodable {
            let deadline: String? = nil
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(deadline, forKey: .deadline)
            }
            enum CodingKeys: String, CodingKey { case deadline }
        }
        try await client.from("rewards").update(Clear()).eq("id", value: id).execute()
    }

    func delete(_ reward: Reward) async throws {
        // Remove the private object first. If storage rejects the request, keep
        // the row so the user can retry instead of silently orphaning the file.
        if let path = reward.photoPath {
            _ = try await client.storage.from(bucket).remove(paths: [path])
        }
        try await client.from("rewards").delete().eq("id", value: reward.id).execute()
    }

    func signedURL(path: String, expiresIn: Int = 3600) async throws -> URL {
        try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: expiresIn)
    }

    /// Removes every reward photo this user has uploaded - done before deleting the account,
    /// since stored files can't be removed from the database side.
    func deleteAllFiles() async throws {
        let paths = try await fetchAll().compactMap(\.photoPath)
        guard !paths.isEmpty else { return }
        for start in stride(from: 0, to: paths.count, by: 100) {
            _ = try await client.storage.from(bucket).remove(paths: Array(paths[start..<min(start + 100, paths.count)]))
        }
    }
}

/// The streak moments already recorded, so each one shows once.
struct StreakEventRepository {
    let client = SupabaseService.shared.client

    private struct NewEvent: Encodable {
        let user_id: UUID
        let date: String
        let kind: String
        let value: Int?
    }

    /// Records the events that aren't stored yet and returns exactly those. An event already stored
    /// (same date and kind) is skipped, so it never fires twice.
    func recordNew(_ events: [StreakEvent]) async throws -> [StreakEvent] {
        guard !events.isEmpty else { return [] }
        let userId = try await client.auth.session.user.id
        struct Stored: Decodable { let date: String; let kind: String }
        let stored: [Stored] = try await client
            .from("streak_events")
            .upsert(
                events.map { NewEvent(user_id: userId, date: $0.date, kind: $0.kind.rawValue, value: $0.value) },
                onConflict: "user_id,date,kind",
                ignoreDuplicates: true
            )
            .select("date,kind")
            .execute()
            .value
        let added = Set(stored.map { "\($0.date)-\($0.kind)" })
        return events.filter { added.contains("\($0.date)-\($0.kind.rawValue)") }
    }
}
