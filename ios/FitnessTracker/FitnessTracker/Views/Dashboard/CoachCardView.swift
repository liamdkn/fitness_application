import SwiftUI

/// The Dashboard's coach card: one message for today, one action, this week as seven squares.
struct CoachCardView: View {
    @ObservedObject var viewModel: CoachViewModel

    var body: some View {
        if let message = viewModel.message, viewModel.snapshot != nil {
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

                    NavigationLink {
                        CoachPatternsView(viewModel: viewModel)
                    } label: {
                        HStack(spacing: 6) {
                            if let week = viewModel.thisWeek {
                                ForEach(week.cells) { cell in
                                    StarCell(
                                        cell: cell,
                                        kind: viewModel.stars?.byDate[DateFormatting.isoDate(cell.date)] ?? .none,
                                        celebrate: viewModel.celebratingDate == DateFormatting.isoDate(cell.date)
                                    )
                                    .frame(width: 30, height: 30)
                                }
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 0) {
                                Label("\(viewModel.streak?.displayCurrent ?? 0)", systemImage: "flame.fill")
                                    .font(.title3.bold())
                                    .foregroundStyle(AppColor.flame)
                                Text(viewModel.streak.map { "best \($0.best)" } ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CoachPatternsView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("Star chart and patterns")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private func perform(_ action: CoachMessage.Action) {
        switch action {
        case .startWorkout: CoachRouter.shared.openTrain()
        case .openNutrition(let days): CoachRouter.shared.openNutrition(daysFromToday: days)
        case .logTreat: CoachRouter.shared.openNutrition(daysFromToday: 0)
        }
    }
}
