import SwiftUI

/// Shared four-Dot brand mark for the splash and sign-in screens.
/// Uses the same artwork as the app icon so the brand stays consistent.
struct GameLogoMark: View {
    var size: CGFloat = 220
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate * 1.7
                artwork
                    .scaleEffect(1 + sin(phase) * 0.015)
                    .rotationEffect(.degrees(sin(phase * 0.7) * 1.4))
                    .offset(y: sin(phase) * size * 0.025)
            }
        } else {
            artwork
        }
    }

    private var artwork: some View {
        Image("GameLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Space - Dots & AI")
    }
}

/// A timed launch screen with the shared logo and loading indicator.
struct SplashView: View {
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            GameLogoMark(size: 280, animated: !reduceMotion)

            VStack(spacing: 10) {
                Spacer()
                LoadingDots()
                Text("Powered by Spacechat")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 36)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                onFinished()
            }
        }
    }
}

/// A small four-dot "loading" indicator — each dot rises and brightens in
/// turn — so the splash beat reads as something actively happening rather
/// than a static logo sitting there for 1.8 seconds.
private struct LoadingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors: [Color] = [.cyan, .pink, .green, .blue]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0..<4) { i in
                    let phase = t * 3.2 - Double(i) * 0.9
                    let bounce = reduceMotion ? 0 : max(0, sin(phase))
                    Circle()
                        .fill(colors[i])
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * bounce)
                        .offset(y: -CGFloat(bounce) * 4)
                }
            }
        }
        .frame(height: 14)
    }
}
