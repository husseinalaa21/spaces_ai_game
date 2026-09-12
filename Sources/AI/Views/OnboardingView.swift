import SwiftUI

/// First-launch sequence, verbatim pacing from §61: pure white, a dot appears,
/// "This is you.", "Move.", eat one icon, "Everything you eat changes you.",
/// then straight into the game. No multi-page tutorial.
struct OnboardingView: View {
    let onFinished: () -> Void

    private enum Step { case dotAppears, thisIsYou, move, waitingForMove, eatIt, waitingForEat, changesYou }
    @State private var step: Step = .dotAppears
    @State private var dragOffset: CGSize = .zero
    @State private var hasMoved = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            // The dot itself.
            if step != .dotAppears {
                Circle()
                    .fill(Color(white: 0.16))
                    .frame(width: 30, height: 30)
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard step == .waitingForMove || step == .move else { return }
                                dragOffset = value.translation
                                if !hasMoved, abs(value.translation.width) + abs(value.translation.height) > 24 {
                                    hasMoved = true
                                    advance(to: .eatIt, after: 0.6)
                                }
                            }
                    )
                    .animation(.easeOut(duration: 0.3), value: dragOffset)
            }

            if step == .waitingForEat || step == .eatIt {
                Text("🍌")
                    .font(.system(size: 22))
                    .offset(x: dragOffset.width + 90, y: dragOffset.height - 10)
                    .onTapGesture { advance(to: .changesYou, after: 0.4) }
            }

            VStack {
                Spacer()
                Text(caption)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.8))
                    .padding(.bottom, 80)
                    .transition(.opacity)
                    .id(caption)
            }
        }
        .onAppear { runIntro() }
    }

    private var caption: String {
        switch step {
        case .dotAppears: return ""
        case .thisIsYou: return "This is you."
        case .move, .waitingForMove: return "Move."
        case .eatIt, .waitingForEat: return "Eat it."
        case .changesYou: return "Everything you eat changes you."
        }
    }

    private func runIntro() {
        advance(to: .thisIsYou, after: 0.5)
        advance(to: .move, after: 2.0)
        advance(to: .waitingForMove, after: 2.1)
    }

    private func advance(to newStep: Step, after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation { step = newStep }
            if newStep == .waitingForEat {
                // fallback: allow tap without strict gating
            }
            if newStep == .changesYou {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    onFinished()
                }
            }
        }
    }
}
