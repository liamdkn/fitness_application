import Foundation
import Supabase

/// Everything a daily check-in writes, captured so it can be sent later:
/// the check-in row, the weigh-in, the waist, and the sleep entry.
struct QueuedDailyCheckin: Codable {
    let date: Date
    let weightKg: Double?
    let routineDayId: UUID?
    let workoutChoiceLabel: String?
    let isRestDay: Bool
    let energyLevel: Int
    let sorenessLevel: Int
    let yesterdayWaterMl: Int?
    let yesterdayOffPlan: Bool
    let yesterdayOffPlanNotes: String?
    /// 1-5, nil when not rated (and for check-ins queued by older builds).
    let yesterdayHungerLevel: Int?
    /// How yesterday is flagged: "sick", "not_tracked", or "normal" to clear it. Nil leaves it
    /// as it is (check-ins queued by older builds).
    var yesterdayStatus: String? = nil
    /// Only set when the user changed it - an unchanged Health-synced value
    /// isn't written back.
    let sleepMinutes: Int?
    /// Waist in cm, entered under the weight (nil for check-ins queued by older builds).
    var waistCm: Double? = nil
}

/// The three writes a daily check-in makes, in order. Used when saving
/// normally and when replaying one that was queued offline - connection
/// failures propagate (so the caller can queue or retry), anything else on the
/// weight and sleep steps is ignored as before.
enum DailyCheckinSubmitter {
    @MainActor
    static func submit(_ checkin: QueuedDailyCheckin, ownerId: UUID) async throws {
        guard SupabaseService.shared.session?.user.id == ownerId else { throw OfflineQueueError.signInRequired }
        try await DailyCheckinRepository().save(
            ownerId: ownerId,
            date: checkin.date,
            weightKg: checkin.weightKg,
            routineDayId: checkin.routineDayId,
            workoutChoiceLabel: checkin.workoutChoiceLabel,
            isRestDay: checkin.isRestDay,
            energyLevel: checkin.energyLevel,
            sorenessLevel: checkin.sorenessLevel,
            yesterdayWaterMl: checkin.yesterdayWaterMl,
            yesterdayOffPlan: checkin.yesterdayOffPlan,
            yesterdayOffPlanNotes: checkin.yesterdayOffPlanNotes,
            yesterdayHungerLevel: checkin.yesterdayHungerLevel
        )

        if let status = checkin.yesterdayStatus,
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: checkin.date) {
            guard SupabaseService.shared.session?.user.id == ownerId else { throw OfflineQueueError.signInRequired }
            try await DayFlagRepository().set(date: yesterday, status: DayStatus(rawValue: status), ownerId: ownerId)
        }

        if let weightKg = checkin.weightKg {
            guard SupabaseService.shared.session?.user.id == ownerId else { throw OfflineQueueError.signInRequired }
            let bodyWeight = BodyWeightRepository()
            var updated: BodyWeightLog?
            do {
                updated = try await bodyWeight.updateTodaysWeight(kg: weightKg, ownerId: ownerId)
            } catch {
                if OfflineError.isConnectivity(error) { throw error }
            }
            if updated == nil {
                do {
                    _ = try await bodyWeight.logWeight(kg: weightKg, ownerId: ownerId)
                } catch {
                    if OfflineError.isConnectivity(error) { throw error }
                }
            }
        }

        if let waistCm = checkin.waistCm {
            do {
                guard SupabaseService.shared.session?.user.id == ownerId else { throw OfflineQueueError.signInRequired }
                try await BodyMeasurementRepository().saveDailyWaist(cm: waistCm, date: checkin.date, ownerId: ownerId)
            } catch {
                if OfflineError.isConnectivity(error) { throw error }
            }
        }

        if let minutes = checkin.sleepMinutes {
            do {
                guard SupabaseService.shared.session?.user.id == ownerId else { throw OfflineQueueError.signInRequired }
                try await HealthRepository().upsertSleep([
                    SleepLog(
                        userId: ownerId,
                        date: DateFormatting.isoDate(checkin.date),
                        totalSleepMinutes: minutes,
                        inBedMinutes: minutes,
                        source: "manual"
                    )
                ])
            } catch {
                if OfflineError.isConnectivity(error) { throw error }
            }
        }
    }
}

/// A small persistent queue of writes made with no signal - water logs and
/// daily check-ins (with their weigh-in and sleep) - sent in order when the
/// connection returns. Meals and workouts have their own, richer queues
/// (`OfflineMealQueue`, `OfflineWorkoutQueue`); this covers the smaller ones.
/// Every operation is safe to replay: water logs carry a client-made id and
/// are upserted, deletes are by id, and a check-in is an upsert per day.
@MainActor
final class OfflineOutbox {
    static let shared = OfflineOutbox()

    enum Operation: Codable {
        case addWater(WaterLog)
        case deleteWater(UUID)
        case dailyCheckin(QueuedDailyCheckin)
        case addSupplementLog(SupplementLog)
        case deleteSupplementLog(UUID)
    }

    struct Entry: Codable {
        let id: UUID
        let operation: Operation
        var attempts: Int
        /// Who queued it. Never sent under anyone else's session. `nil` only
        /// for entries saved before owners were recorded (see `adoptUnowned`).
        var ownerId: UUID?
    }

    private(set) var entries: [Entry] = []
    private var isFlushing = false
    private var retryTask: Task<Void, Never>?
    private static let maxAttempts = 5
    private static let retryInterval: TimeInterval = 20

    private let fileURL = URL.applicationSupportDirectory.appending(path: "offline-outbox.json")

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
        NetworkMonitor.shared.onReconnected { [weak self] in
            Task { await self?.flush() }
        }
        if !entries.isEmpty { scheduleRetry() }
    }

    var hasPending: Bool { !entries.isEmpty }

    func enqueue(_ operation: Operation) throws {
        guard let ownerId = SupabaseService.shared.session?.user.id else { throw OfflineQueueError.signInRequired }
        entries.append(Entry(id: UUID(), operation: operation, attempts: 0, ownerId: ownerId))
        persist()
        scheduleRetry()
    }

    // MARK: Water, as the screens should see it while writes are pending

    /// A water log that hasn't reached the server yet is dropped outright if
    /// it's deleted - it never needs to. Returns true when that happened.
    /// Entries from before owners were recorded belong to the one person who
    /// has been using this phone: give them to the account that's signed in now.
    func adoptUnowned(by userId: UUID) {
        var changed = false
        for index in entries.indices where entries[index].ownerId == nil {
            entries[index].ownerId = userId
            changed = true
        }
        if changed { persist() }
    }

    /// Removes everything queued - at sign-out or when a different account
    /// signs in (see `LocalData`).
    func wipeAll() {
        entries = []
        retryTask?.cancel()
        retryTask = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    func cancelPendingAddWater(id: UUID) -> Bool {
        guard let ownerId = SupabaseService.shared.session?.user.id else { return false }
        guard let index = entries.firstIndex(where: {
            if case .addWater(let log) = $0.operation { return log.id == id && $0.ownerId == ownerId }
            return false
        }) else { return false }
        entries.remove(at: index)
        persist()
        return true
    }

    func cancelPendingSupplementLog(id: UUID) -> Bool {
        guard let ownerId = SupabaseService.shared.session?.user.id else { return false }
        guard let index = entries.firstIndex(where: {
            if case .addSupplementLog(let log) = $0.operation { return log.id == id && $0.ownerId == ownerId }
            return false
        }) else { return false }
        entries.remove(at: index)
        persist()
        return true
    }

    /// Same as `applyingPendingWater`, for supplement doses.
    func applyingPendingSupplementLogs(to logs: [SupplementLog], date: String) -> [SupplementLog] {
        guard let ownerId = SupabaseService.shared.session?.user.id else { return logs }
        var result = logs
        var deletedIds = Set<UUID>()
        for entry in entries where entry.ownerId == ownerId {
            switch entry.operation {
            case .addSupplementLog(let log) where log.date == date && !result.contains(where: { $0.id == log.id }):
                result.append(log)
            case .deleteSupplementLog(let id):
                deletedIds.insert(id)
            default:
                break
            }
        }
        return result.filter { !deletedIds.contains($0.id) }.sorted { $0.takenAt < $1.takenAt }
    }

    /// `logs` for `date` with pending adds included and pending deletes hidden.
    func applyingPendingWater(to logs: [WaterLog], date: String) -> [WaterLog] {
        guard let ownerId = SupabaseService.shared.session?.user.id else { return logs }
        var result = logs
        var deletedIds = Set<UUID>()
        for entry in entries where entry.ownerId == ownerId {
            switch entry.operation {
            case .addWater(let log) where log.date == date && !result.contains(where: { $0.id == log.id }):
                result.append(log)
            case .deleteWater(let id):
                deletedIds.insert(id)
            default:
                break
            }
        }
        return result.filter { !deletedIds.contains($0.id) }.sorted { $0.loggedAt < $1.loggedAt }
    }

    // MARK: Sending

    func flush() async {
        guard !isFlushing, !entries.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }
        guard let currentUser = SupabaseService.shared.session?.user.id else { return }

        while SupabaseService.shared.session?.user.id == currentUser,
              let first = entries.first {
            guard first.ownerId == currentUser else {
                // Never send or discard another account's work here. Account
                // switching clears the store; an unknown legacy owner waits for adoption.
                return
            }
            do {
                try await perform(first.operation, ownerId: currentUser)
                // LocalData.wipe() or a new-account queue can run while the
                // request is suspended. Remove only the exact entry we sent.
                guard SupabaseService.shared.session?.user.id == currentUser else { return }
                guard entries.first?.id == first.id else { continue }
                entries.removeFirst()
                persist()
            } catch {
                guard SupabaseService.shared.session?.user.id == currentUser,
                      let index = entries.firstIndex(where: { $0.id == first.id }) else { return }
                if !OfflineError.isConnectivity(error) {
                    entries[index].attempts += 1
                    if entries[index].attempts >= Self.maxAttempts { entries.remove(at: index) }
                    persist()
                }
                break
            }
        }
        if entries.isEmpty { retryTask?.cancel() } else { scheduleRetry() }
    }

    private func perform(_ operation: Operation, ownerId: UUID) async throws {
        switch operation {
        case .addWater(let log):
            try await WaterRepository().upsertLog(log, ownerId: ownerId)
        case .deleteWater(let id):
            try await WaterRepository().deleteLogOnServer(id: id)
        case .dailyCheckin(let checkin):
            try await DailyCheckinSubmitter.submit(checkin, ownerId: ownerId)
        case .addSupplementLog(let log):
            try await SupplementRepository().upsertLog(log, ownerId: ownerId)
        case .deleteSupplementLog(let id):
            try await SupplementRepository().deleteLogOnServer(id: id)
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil || retryTask?.isCancelled == true else { return }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.retryInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if self.entries.isEmpty { self.retryTask = nil; return }
                await self.flush()
            }
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Best effort - the in-memory queue still works for this session.
        }
    }
}
