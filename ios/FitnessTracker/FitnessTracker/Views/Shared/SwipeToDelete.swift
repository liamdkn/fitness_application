import SwiftUI

/// Slide a row left to act on it, like a list row - for cards that live in a
/// ScrollView rather than a List. A short slide shows the action's button; a long
/// one performs it straight away. Vertical scrolling still works: the slide only
/// starts when the finger moves more sideways than up or down.
private struct SwipeAction: ViewModifier {
    let icon: String
    let tint: Color
    let label: String
    let destructive: Bool
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let onTrigger: () -> Void

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDragging = false

    private let revealWidth: CGFloat = 88
    private let fullSwipe: CGFloat = 220

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled { swipeable(content) } else { content }
    }

    private func swipeable(_ content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // The button under the card, shown as the card slides away.
            Button(role: destructive ? .destructive : nil) {
                withAnimation(.snappy) { offset = 0 }
                onTrigger()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.title3)
                    if !destructive {
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius))
            }
            .buttonStyle(.plain)
            .opacity(offset < 0 ? 1 : 0)
            .accessibilityLabel(label)

            content
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            if !isDragging {
                                // Only a mostly-sideways move starts a slide.
                                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                                isDragging = true
                                dragStartOffset = offset
                            }
                            offset = min(0, dragStartOffset + value.translation.width)
                        }
                        .onEnded { value in
                            defer { isDragging = false }
                            guard isDragging else { return }
                            let end = dragStartOffset + value.predictedEndTranslation.width * 0.4 + value.translation.width * 0.6
                            if end < -fullSwipe {
                                withAnimation(.snappy) { offset = -600 }
                                onTrigger()
                                Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    offset = 0
                                }
                            } else {
                                withAnimation(.snappy) { offset = end < -revealWidth / 2 ? -revealWidth : 0 }
                            }
                        }
                )
        }
    }
}

extension View {
    /// Slide left to delete; see `SwipeAction`.
    func swipeToDelete(cornerRadius: CGFloat = 14, perform onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeAction(icon: "trash.fill", tint: AppColor.danger, label: "Delete", destructive: true,
                             isEnabled: true, cornerRadius: cornerRadius, onTrigger: onDelete))
    }

    /// Slide left for a non-destructive action (a short slide shows its button, a long one does it).
    /// Does nothing while `isEnabled` is false.
    func swipeAction(_ label: String, icon: String, isEnabled: Bool = true, cornerRadius: CGFloat = 12,
                     perform action: @escaping () -> Void) -> some View {
        modifier(SwipeAction(icon: icon, tint: AppColor.accent, label: label, destructive: false,
                             isEnabled: isEnabled, cornerRadius: cornerRadius, onTrigger: action))
    }
}
