import Foundation
import Supabase

struct BodyMeasurementRepository {
    let client = SupabaseService.shared.client

    private struct NewBodyMeasurement: Encodable {
        let user_id: UUID
        let measured_at: String
        let waist_cm: Double?
        let left_bicep_cm: Double?
        let right_bicep_cm: Double?
        let goal_id: UUID?
        let weekly_checkin_id: UUID?
        let source: String
    }

    func fetchRecent(limit: Int = 30) async throws -> [BodyMeasurement] {
        try await client
            .from("body_measurements")
            .select()
            .order("measured_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Measurements logged against a specific weekly check-in - used by the
    /// check-in history/detail screen under Settings.
    func fetchForWeeklyCheckin(_ weeklyCheckinId: UUID) async throws -> [BodyMeasurement] {
        try await client
            .from("body_measurements")
            .select()
            .eq("weekly_checkin_id", value: weeklyCheckinId)
            .order("measured_at", ascending: false)
            .execute()
            .value
    }

    /// Today's waist from the daily check-in, if one was already entered (so reopening the
    /// check-in shows it).
    func waist(on date: Date) async throws -> Double? {
        let rows: [BodyMeasurement] = try await client
            .from("body_measurements")
            .select()
            .eq("measured_at", value: DateFormatting.isoDate(date))
            .not("waist_cm", operator: .is, value: "null")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.waistCm
    }

    private struct WaistUpdate: Encodable { let waist_cm: Double }

    /// The daily check-in's waist: one reading a day. A row already logged that day (here, with a
    /// weekly check-in, or earlier today) has its waist replaced rather than a second row added,
    /// so re-saving a check-in never piles up duplicates. Safe to replay from the offline queue.
    func saveDailyWaist(cm: Double, date: Date, ownerId: UUID) async throws {
        let rows: [BodyMeasurement] = try await client
            .from("body_measurements")
            .select()
            .eq("measured_at", value: DateFormatting.isoDate(date))
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        if let row = rows.first {
            try await client.from("body_measurements").update(WaistUpdate(waist_cm: cm)).eq("id", value: row.id).execute()
        } else {
            try await log(waistCm: cm, leftBicepCm: nil, rightBicepCm: nil, goalId: nil, source: "manual", date: date, ownerId: ownerId)
        }
    }

    func delete(id: UUID) async throws {
        try await client.from("body_measurements").delete().eq("id", value: id).execute()
    }

    @discardableResult
    func log(
        waistCm: Double?,
        leftBicepCm: Double?,
        rightBicepCm: Double?,
        goalId: UUID?,
        weeklyCheckinId: UUID? = nil,
        source: String,
        date: Date = Date(),
        ownerId: UUID? = nil
    ) async throws -> BodyMeasurement {
        let userId: UUID
        if let ownerId { userId = ownerId } else { userId = try await client.auth.session.user.id }
        let inserted: [BodyMeasurement] = try await client
            .from("body_measurements")
            .insert(NewBodyMeasurement(
                user_id: userId,
                measured_at: DateFormatting.isoDate(date),
                waist_cm: waistCm,
                left_bicep_cm: leftBicepCm,
                right_bicep_cm: rightBicepCm,
                goal_id: goalId,
                weekly_checkin_id: weeklyCheckinId,
                source: source
            ))
            .select()
            .execute()
            .value
        guard let measurement = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return measurement
    }
}
