import SwiftUI

/// The app's launch screen: the logo's dot cluster gently shaking in place
/// (loading), with "Powered by Spacechat" pinned at the bottom. Purely a
/// timed loading beat — `onFinished` decides where to go next (sign-in or
/// straight into the game) based on whatever auth state it finds.
struct SplashView: View {
    let onFinished: () -> Void

    private struct DotSpec {
        let offset: CGPoint   // from the cluster's own center, in points
        let color: Color
        let seed: Double
    }

    // Mirrors the app's dot logo: one blue dot off to the side, a loose ring
    // of black dots, none touching.
    private let dots: [DotSpec]

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        let black = Color(white: 0.10)
        dots = [
            DotSpec(offset: CGPoint(x: -46, y: -36), color: Color(red: 41/255, green: 121/255, blue: 255/255), seed: 0.0),
            DotSpec(offset: CGPoint(x: 2, y: -26), color: black, seed: 1.3),
            DotSpec(offset: CGPoint(x: 30, y: -14), color: black, seed: 2.6),
            DotSpec(offset: CGPoint(x: -22, y: 8), color: black, seed: 3.9),
            DotSpec(offset: CGPoint(x: 8, y: 22), color: black, seed: 5.1),
            DotSpec(offset: CGPoint(x: 38, y: 18), color: black, seed: 6.4),
            DotSpec(offset: CGPoint(x: -6, y: 44), color: black, seed: 7.7),
        ]
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: size.width / 2, y: size.height / 2 - 16)
                    for dot in dots {
                        let shakeX = CGFloat(sin(t * 10 + dot.seed) * 2.6 + sin(t * 3.3 + dot.seed) * 1.2)
                        let shakeY = CGFloat(cos(t * 12 + dot.seed * 1.4) * 2.6)
                        let pos = CGPoint(x: center.x + dot.offset.x + shakeX,
                                           y: center.y + dot.offset.y + shakeY)
                        DotRenderer.draw(context, center: pos, radius: 13, color: dot.color)
                    }
                }
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
