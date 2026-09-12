import SwiftUI

/// Shown right after sign-in (or straight after the splash screen, for a
/// returning player), before White Space actually starts. One animated
/// preview of the player dot — the same blue as the app's own logo dot,
/// no card/background around it — and a single Play button at the bottom.
/// White Space itself only starts once the player taps Play (`RootView`
/// doesn't build the world until then).
struct MainMenuView: View {
    let onPlay: () -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text("Spaces - AI Game")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 24)

                PlayPreviewDot()

                Spacer()

                Button(action: onPlay) {
                    Text("Play")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 220, height: 54)
                }
                .background(Color.black)
                .clipShape(Capsule())
                .padding(.bottom, 48)
            }
        }
    }
}

/// A single, self-animating preview of the player dot — the same blue as
/// the app's own logo dot, drawn directly on the menu's white background
/// (no card/box around it), with plain white eyes (no pupil) to match the
/// logo's clean look. Uses the same squash-and-stretch body as the real
/// in-game player (`DotRenderer.drawPlayer`), just driven by a scripted
/// loop instead of real drag input.
private struct PlayPreviewDot: View {
    private let blue = Color(red: 41 / 255, green: 121 / 255, blue: 255 / 255)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let stretch = CGFloat(0.3 + 0.3 * (0.5 + 0.5 * sin(t * 1.8)))
                let angle = Angle(radians: sin(t * 0.9) * 1.1)
                DotRenderer.drawPlayer(context, center: center, radius: 44, color: blue,
                                        stretch: stretch, angle: angle,
                                        lookDirection: .zero, time: t, eyeStyle: .whiteOnly)
            }
        }
        .frame(width: 140, height: 140)
    }
}
