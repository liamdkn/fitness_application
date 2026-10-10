import Foundation
import Supabase

struct DayFlagRepository {
    let client = SupabaseService.shared.client

    private struct NewFlag: Encodable {
        let user_id: UUID
        let date: String
        let status: String
    }

    func fetchRange(from: Date, to: Date) async throws -> [DayFlag] {
        try await client
            .from("day_flags")
            .select("date, status")
            .gte("date", value: DateFormatting.isoDate(from))
            .lte("date", value: DateFormatting.isoDate(to))
            .order("date")
            .execute()
            .value
    }

    func fetch(date: Date) async throws -> DayFlag? {
        let flags: [DayFlag] = try await client
            .from("day_flags")
            .select("date, status")
            .eq("date", value: DateFormatting.isoDate(date))
            .limit(1)
            .execute()
            .value
        return flags.first
    }

    /// Marks a day, or clears it with `nil`.
    func set(date: Date, status: DayStatus?) async throws {
        let day = DateFormatting.isoDate(date)
        guard let status else {
            try await client.from("day_flags").delete().eq("date", value: day).execute()
            return
        }
        let userId = try await client.auth.session.user.id
        try await client
            .from("day_flags")
            .upsert(NewFlag(user_id: userId, date: day, status: status.rawValue), onConflict: "user_id,date")
            .execute()
    }
}
