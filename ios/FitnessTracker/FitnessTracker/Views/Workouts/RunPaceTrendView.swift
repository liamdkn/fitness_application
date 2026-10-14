import Charts
import SwiftUI

/// Average pace of each finished run, by the type of run it was planned as - easy, tempo, long -
/// so the trend in each is visible on its own.
struct RunPaceTrendView: View {
    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let paceSec: Double
        let km: Double
    }

    /// Run types in the order shown, with their points oldest first.
    let series: [(type: RunType, points: [Point])]

    var body: some View {
        List {
            if series.allSatisfy({ $0.points.count < 2 }) {
                Text("Pace trends show once a type of run has been done a couple of times.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(series.filter { $0.points.count >= 2 }, id: \.type) { entry in
                Section {
                    chart(entry.points)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: {
                    Text(entry.type.displayName)
                } footer: {
                    if let first = entry.points.first, let last = entry.points.last {
                        Text("\(Self.paceText(first.paceSec)) to \(Self.paceText(last.paceSec)) over \(entry.points.count) runs")
                    }
                }
                .listRowBackground(AppRowBackground())
            }
        }
        .appScreen()
        .navigationTitle("Pace Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chart(_ points: [Point]) -> some View {
        Chart(points) { point in
            LineMark(x: .value("Date", point.date), y: .value("Pace", point.paceSec))
                .foregroundStyle(AppColor.accent)
            PointMark(x: .value("Date", point.date), y: .value("Pace", point.paceSec))
                .foregroundStyle(AppColor.accent)
        }
        // Faster (a lower number) is higher up.
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) { Text(Self.paceText(seconds)) }
                }
            }
        }
        .frame(height: 160)
    }

    /// 345 -> "5:45/km".
    static func paceText(_ seconds: Double) -> String {
        PaceText.format(Int(seconds.rounded()))
    }
}
