import SwiftUI

/// One day on the star chart. An on-plan day is a star, today looking on plan is a hollow star,
/// a freeze-covered slip carries a snowflake, a barely logged day is a dashed outline, other off
/// days are plain grey, and days still to come are empty outlines.
struct StarCell: View {
    let cell: CoachWeekCell
    let kind: StarKind
    /// Pulse once: this star was just confirmed.
    var celebrate = false

    @State private var pulsing = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6) }

    var body: some View {
        content
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(pulsing ? 1.4 : 1)
            .shadow(color: AppColor.star.opacity(pulsing ? 0.9 : 0), radius: pulsing ? 10 : 0)
            .onAppear { if celebrate { pulse() } }
            .onChange(of: celebrate) { _, now in if now { pulse() } }
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var content: some View {
        if !cell.inPhase {
            shape.strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
        } else if kind == .filled {
            shape.fill(AppColor.star.opacity(0.2))
                .overlay { Image(systemName: "star.fill").font(.caption).foregroundStyle(AppColor.star).symbolEffect(.bounce, value: celebrate) }
        } else if kind == .provisional {
            shape.strokeBorder(AppColor.star.opacity(0.6), lineWidth: 1.5)
                .overlay { Image(systemName: "star").font(.caption).foregroundStyle(AppColor.star) }
        } else if kind == .frozen {
            shape.fill(Color.secondary.opacity(0.3))
                .overlay { Image(systemName: "snowflake").font(.caption2).foregroundStyle(AppColor.freeze) }
        } else if let record = cell.record {
            if record.status == .blank, !record.isSick {
                shape.strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else {
                shape.fill(Color.secondary.opacity(0.3))
                    .overlay { if record.isSick { Circle().fill(.white.opacity(0.85)).frame(width: 6, height: 6) } }
            }
        } else {
            shape.strokeBorder(Color.secondary.opacity(cell.isToday ? 0.9 : 0.3), lineWidth: cell.isToday ? 2 : 1)
        }
    }

    private func pulse() {
        Task {
            withAnimation(.spring(duration: 0.45, bounce: 0.55)) { pulsing = true }
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.4)) { pulsing = false }
        }
    }

    private var label: String {
        let day = cell.date.formatted(.dateTime.weekday(.wide).day().month())
        switch kind {
        case .filled: return "\(day): star"
        case .provisional: return "\(day): star so far, confirmed tomorrow"
        case .frozen: return "\(day): off plan, covered by a streak freeze"
        case .none:
            guard let record = cell.record else { return "\(day): not finished" }
            return "\(day): \(record.status.displayName)\(record.isSick ? ", sick" : "")"
        }
    }
}
