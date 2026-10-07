import SwiftUI

/// How today's water compares with where it should be by now, and with
/// earlier days at the same time: "400 ml behind - drink a glass to catch up".
struct WaterPaceSection: View {
    let day: LiquidsDay
    let preferences: UserPreferences?
    let glassMl: Int

    @State private var pastDays: [LiquidsDay] = []
    @State private var wakeMinutes = 7 * 60
    @State private var endMinutes = 20 * 60

    private let liquidsRepository = LiquidsRepository()

    private var target: Double { Double(preferences?.dailyWaterMlTargetMin ?? 2000) }
    private var nowMinute: Int { WaterPace.minuteOfDay(Date()) }

    private var expected: Double {
        WaterPace.expectedMl(atMinute: nowMinute, wakeMinutes: wakeMinutes, endMinutes: endMinutes, targetMl: target)
    }

    private var behind: Double { expected - day.hydrationMl }

    private func items(_ day: LiquidsDay) -> [(time: Date, ml: Double)] {
        day.items.map { ($0.time, $0.volumeMl) }
    }

    private func at(_ day: LiquidsDay) -> Double {
        WaterPace.ml(in: items(day), byMinute: nowMinute)
    }

    /// Average of the days that have anything logged.
    private var usualByNow: Double? {
        let logged = pastDays.filter { !$0.items.isEmpty }
        guard logged.count >= 3 else { return nil }
        return logged.map(at).reduce(0, +) / Double(logged.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if nowMinute < wakeMinutes || nowMinute >= endMinutes || behind < 100 {
                Label("On pace for today", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.success)
            } else {
                let glasses = WaterPace.glassesToCatchUp(behindMl: behind, glassMl: glassMl)
                let behindText = "About \(Int((behind / 50).rounded()) * 50) ml behind pace."
                // Chugging a litre and a half isn't the advice - a glass now,
                // then steady sipping, is.
                let advice = glasses <= 2
                    ? "Drink \(glasses == 1 ? "a glass" : "2 glasses") (\(glasses * glassMl) ml) to catch up."
                    : "Have a glass (\(glassMl) ml) now, then keep sipping through the afternoon."
                Label("\(behindText) \(advice)", systemImage: "drop.fill")
                    .foregroundStyle(AppColor.water)
            }
            if let comparison {
                Text(comparison)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    /// "Yesterday by now 1.2 L - usually 1.1 L", whichever are known.
    private var comparison: String? {
        var parts: [String] = []
        if let yesterday = pastDays.first, !yesterday.items.isEmpty { parts.append("Yesterday by now \(format(at(yesterday)))") }
        if let usualByNow { parts.append("Usually \(format(usualByNow))") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00b7} ")
    }

    private func format(_ ml: Double) -> String {
        ml >= 1000 ? String(format: "%.2f L", ml / 1000) : "\(Int(ml.rounded())) ml"
    }

    private func load() async {
        if let wake = await WakeTimeResolver.typicalWakeMinutes() { wakeMinutes = wake }
        let bedtime = await BedtimeResolver.resolve(preferences).minutes
        // Bedtime is after midnight-scaled; keep the end on the same day.
        endMinutes = max(wakeMinutes + 6 * 60, (bedtime < wakeMinutes ? bedtime + 1440 : bedtime) - 120)
        endMinutes = min(endMinutes, 23 * 60)
        var days: [LiquidsDay] = []
        for offset in 1...7 {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()),
                  let fetched = try? await liquidsRepository.fetchDay(date: date) else { continue }
            days.append(fetched)
        }
        pastDays = days
    }
}
