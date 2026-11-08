import SwiftUI
import UIKit

/// A full-screen pause for a milestone, a freeze, a perfect week or a streak that ended. Calm
/// throughout: nothing here ever suggests eating less or doing extra to win a streak back.
struct StreakMomentView: View {
    let moment: StreakMoment
    var onDone: () -> Void

    @State private var grown = false

    private var symbol: String {
        switch moment.kind {
        case .freezeUsed: "snowflake"
        case .freezeEarned: "medal.fill"
        default: "flame.fill"
        }
    }

    private var tint: Color {
        switch moment.kind {
        case .milestone: AppColor.flame
        case .freezeUsed: AppColor.freeze
        case .freezeEarned: AppColor.star
        case .broken: .secondary
        }
    }

    /// The flame grows with the streak.
    private var size: CGFloat { moment.kind == .milestone ? 90 + CGFloat(min(moment.streak, 90)) * 1.2 : 110 }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: size))
                    .foregroundStyle(tint)
                    .scaleEffect(grown ? 1 : 0.3)
                    .shadow(color: tint.opacity(grown && moment.kind != .broken ? 0.6 : 0), radius: 24)
                Text(moment.headline).font(.largeTitle.bold())
                Text(moment.message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                Spacer()
                Button("Continue", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 32)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.5)) { grown = true }
            if moment.kind == .milestone || moment.kind == .freezeEarned {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "You earned it": confetti, the photo large, Claim or Later.
struct RewardUnlockedView: View {
    let progress: RewardProgress
    var onClaim: () -> Void
    var onLater: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            ConfettiView()
            VStack(spacing: 20) {
                Spacer()
                RewardPhotoView(path: progress.reward.photoPath, size: 220, cornerRadius: 24)
                    .shadow(color: AppColor.star.opacity(0.5), radius: 20)
                Text("You earned it").font(.title3).foregroundStyle(.secondary)
                Text(progress.reward.title).font(.largeTitle.bold()).multilineTextAlignment(.center).padding(.horizontal, 24)
                Text(progress.reward.goalKind.targetText(progress.target))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(spacing: 12) {
                    Button(progress.reward.link == nil ? "Claim" : "Claim and open link", action: onClaim)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("Later", action: onLater)
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}

/// Paper falling from the top, for a few seconds, then nothing.
struct ConfettiView: View {
    private struct Piece {
        let x: Double, speed: Double, sway: Double, phase: Double, spin: Double, size: Double, color: Int, delay: Double
        nonisolated init(_ i: Int) {
            // Deterministic scatter, so no random source is needed.
            func unit(_ n: Int, _ k: Double) -> Double { abs(sin(Double(n) * k)).truncatingRemainder(dividingBy: 1) }
            x = unit(i, 12.9898); speed = 120 + unit(i, 78.233) * 160; sway = 1 + unit(i, 37.719) * 3
            phase = unit(i, 4.1414) * 6.28; spin = unit(i, 9.1317) * 8 - 4; size = 6 + unit(i, 2.7183) * 6
            color = i % 5; delay = unit(i, 15.37) * 1.2
        }
    }

    private let pieces = (0..<80).map(Piece.init)
    private let colors: [Color] = [AppColor.star, AppColor.accent, AppColor.success, AppColor.warning, AppColor.flame]
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { graphics, canvas in
                let elapsed = context.date.timeIntervalSince(start)
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -20 + t * piece.speed
                    guard y < canvas.height + 20 else { continue }
                    let x = piece.x * canvas.width + sin(t * piece.sway + piece.phase) * 24
                    var context = graphics
                    context.translateBy(x: x, y: y)
                    context.rotate(by: .radians(t * piece.spin))
                    context.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)), with: .color(colors[piece.color]))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The Dashboard's slim card for the reward that's closest.
struct NearestRewardCard: View {
    @ObservedObject var viewModel: CoachViewModel

    var body: some View {
        if let progress = viewModel.nearestReward {
            NavigationLink {
                RewardsView()
            } label: {
                DashboardCard {
                    HStack(spacing: 12) {
                        RewardPhotoView(path: progress.reward.photoPath, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(progress.reward.title).font(.subheadline.weight(.semibold))
                            ProgressView(value: progress.fraction).tint(AppColor.star)
                            Text(progress.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
