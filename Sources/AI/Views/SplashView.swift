import SwiftUI

/// The app's launch screen: the Vision 1 logo's dot cluster (plain white
/// background, no grid — just the seven glossy dots) redrawn live so each
/// dot can jitter/shake on its own timing, with "Powered by Spacechat"
/// pinned at the bottom while it loads. Purely a timed loading beat —
/// `onFinished` decides where to go next (sign-in or straight into the
/// game) based on whatever auth state it finds.
/// The game's logo: the seven-dot cluster from the app icon (Vision 1),
/// drawn live rather than shipped as a flat image so it can shake.
///
/// One definition, used by both the splash screen and the sign-in page —
/// having each screen redraw its own approximation of the logo is how the
/// two drift apart.
struct GameLogoMark: View {
    var size: CGFloat = 220
    /// Each dot jitters on its own timing. Off for static placements, and
    /// respect Reduce Motion wherever it's on.
    var animated: Bool = true

    private struct DotSpec {
        let position: CGPoint  // fraction (0...1) within the cluster square
        let color: Color
        let freqX: Double
        let freqY: Double
        let phaseX: Double
        let phaseY: Double
        let amplitude: CGFloat
    }

    // Exact cluster layout from the app's own logo generator (same seed as
    // assets/logo.png / "vision one"), so this matches the real logo's dot
    // positions and colors precisely — just without the grid, and with each
    // dot free to shake independently instead of being baked into one image.
    private let dots: [DotSpec] = [
        DotSpec(position: CGPoint(x: 0.673, y: 0.527), color: Color(white: 0.10), freqX: 7.1, freqY: 9.4, phaseX: 0.6, phaseY: 2.1, amplitude: 3.6),
        DotSpec(position: CGPoint(x: 0.602, y: 0.352), color: Color(white: 0.10), freqX: 8.3, freqY: 6.8, phaseX: 1.9, phaseY: 4.0, amplitude: 3.1),
        DotSpec(position: CGPoint(x: 0.421, y: 0.384), color: Color(white: 0.10), freqX: 6.4, freqY: 10.2, phaseX: 3.2, phaseY: 0.9, amplitude: 3.8),
        DotSpec(position: CGPoint(x: 0.312, y: 0.443), color: Color(white: 0.10), freqX: 9.6, freqY: 7.5, phaseX: 4.5, phaseY: 1.6, amplitude: 3.2),
        DotSpec(position: CGPoint(x: 0.405, y: 0.620), color: Color(white: 0.10), freqX: 7.8, freqY: 11.1, phaseX: 2.4, phaseY: 3.4, amplitude: 3.7),
        DotSpec(position: CGPoint(x: 0.613, y: 0.627), color: Color(white: 0.10), freqX: 10.4, freqY: 8.2, phaseX: 5.1, phaseY: 2.8, amplitude: 3.3),
        DotSpec(position: CGPoint(x: 0.315, y: 0.300), color: Color(red: 41/255, green: 121/255, blue: 255/255), freqX: 6.9, freqY: 9.9, phaseX: 0.2, phaseY: 5.5, amplitude: 3.4),
    ]

    private let dotRadiusFraction: CGFloat = 0.045

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                let radius = size * dotRadiusFraction
                // Shake amplitude is authored against the 220pt splash
                // cluster, so it scales with the mark instead of throwing
                // small placements apart.
                let scale = size / 220

                for dot in dots {
                    let shakeX = animated ? CGFloat(sin(t * dot.freqX + dot.phaseX)) * dot.amplitude * scale : 0
                    let shakeY = animated ? CGFloat(cos(t * dot.freqY + dot.phaseY)) * dot.amplitude * scale : 0
                    let center = CGPoint(
                        x: dot.position.x * size + shakeX,
                        y: dot.position.y * size + shakeY
                    )
                    // No drop shadow — the dots are flat everywhere else in
                    // the app, and the logo should match them.
                    DotRenderer.draw(context, center: center, radius: radius, color: dot.color)
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

/// The app's launch screen: the game's logo, shaking, with "Powered by
/// Spacechat" pinned at the bottom while it loads. Purely a timed loading
/// beat — `onFinished` decides where to go next (sign-in or straight into
/// the game) based on whatever auth state it finds.
struct SplashView: View {
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            GameLogoMark(size: 220, animated: !reduceMotion)

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

/// A small three-dot "loading" indicator — each dot rises and brightens in
/// turn — so the splash beat reads as something actively happening rather
/// than a static logo sitting there for 1.8 seconds.
private struct LoadingDots: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0..<3) { i in
                    let phase = t * 3.2 - Double(i) * 0.9
                    let bounce = max(0, sin(phase))
                    Circle()
                        .fill(Color(white: 0.16))
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * bounce)
                        .offset(y: -CGFloat(bounce) * 4)
                }
            }
        }
        .frame(height: 14)
    }
}
