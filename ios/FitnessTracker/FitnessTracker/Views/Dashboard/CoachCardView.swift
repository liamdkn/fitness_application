import SwiftUI

/// The Dashboard's coach card: one message for today, one action, this week as seven squares.
struct CoachCardView: View {
    @ObservedObject var viewModel: CoachViewModel

    var body: some View {
        if let message = viewModel.message, let snapshot = viewModel.snapshot {
            DashboardCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Coach", systemImage: "figure.mind.and.body")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(message.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action = message.action, let title = message.actionTitle {
                        Button(title) { perform(action) }
                            .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 6) {
                        if let week = viewModel.thisWeek {
                            ForEach(week.cells) { cell in
                                square(cell)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(snapshot.onPlanStreak)")
                                .font(.title3.bold())
                            Text(snapshot.onPlanStreak == 1 ? "day on plan" : "days on plan")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        CoachPatternsView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("Calendar and patterns")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    /// Green on plan, grey off plan, outline for today and days to come.
    private func square(_ cell: CoachWeekCell) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        return Group {
            if let record = cell.record {
                shape.fill(record.status.isOn ? AppColor.success : Color.secondary.opacity(0.35))
            } else {
                shape.strokeBorder(Color.secondary.opacity(cell.isToday ? 0.9 : 0.4), lineWidth: cell.isToday ? 2 : 1)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(cell.record.map { "\(cell.date.formatted(.dateTime.weekday(.wide))): \($0.status.displayName)" }
            ?? "\(cell.date.formatted(.dateTime.weekday(.wide))): not finished")
    }

    private func perform(_ action: CoachMessage.Action) {
        switch action {
        case .startWorkout: CoachRouter.shared.openTrain()
        case .openNutrition(let days): CoachRouter.shared.openNutrition(daysFromToday: days)
        case .logTreat: CoachRouter.shared.openNutrition(daysFromToday: 0)
        }
    }
}
