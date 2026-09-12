import SwiftUI

/// The app's launch screen: the Vision 1 logo's dot cluster (plain white
/// background, no grid — just the seven glossy dots) redrawn live so each
/// dot can jitter/shake on its own timing, with "Powered by Spacechat"
/// pinned at the bottom while it loads. Purely a timed loading beat —
/// `onFinished` decides where to go next (sign-in or straight into the
/// game) based on whatever auth state it finds.
struct SplashView: View {
    let onFinished: () -> Void

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
    private let clusterSize: CGFloat = 220

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let radius = clusterSize * dotRadiusFraction

                    for dot in dots {
                        let shakeX = CGFloat(sin(t * dot.freqX + dot.phaseX)) * dot.amplitude
                        let shakeY = CGFloat(cos(t * dot.freqY + dot.phaseY)) * dot.amplitude
                        let center = CGPoint(
                            x: dot.position.x * clusterSize + shakeX,
                            y: dot.position.y * clusterSize + shakeY
                        )

                        // Soft shadow toward the bottom-left, peeking past
                        // the dot's edge — mirrors the top-right highlight
                        // baked into DotRenderer, same as the real logo art.
                        let shadowCenter = CGPoint(x: center.x - radius * 0.55, y: center.y + radius * 0.55)
                        let shadowRadius = radius * 0.7
                        var shadowContext = context
                        shadowContext.opacity = 0.28
                        shadowContext.fill(
                            Path(ellipseIn: CGRect(x: shadowCenter.x - shadowRadius, y: shadowCenter.y - shadowRadius,
                                                    width: shadowRadius * 2, height: shadowRadius * 2)),
                            with: .color(.black)
                        )

                        DotRenderer.draw(context, center: center, radius: radius, color: dot.color)
                    }
                }
                .frame(width: clusterSize, height: clusterSize)
            }

            VStack {
                Spacer()
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
