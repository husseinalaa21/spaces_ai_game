import SwiftUI

/// Shown right after sign-in (or straight after the splash screen, for a
/// returning player), before White Space actually starts. A few animated
/// preview cards up top — a little taste of the moving, eyed dot — and a
/// single Play button at the bottom. White Space itself only starts once
/// the player taps Play (`RootView` doesn't build the world until then).
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

                HStack(spacing: 14) {
                    PlayPreviewCard(phase: 0)
                    PlayPreviewCard(phase: 1.4)
                    PlayPreviewCard(phase: 2.8)
                }
                .padding(.horizontal, 20)

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

/// A small, self-animating preview of the player dot — the same
/// squash-and-stretch body and blinking/glancing eyes as the real thing
/// (`DotRenderer.drawPlayer`), just driven by a scripted loop instead of
/// real drag input, so the menu shows a little life before you even play.
private struct PlayPreviewCard: View {
    let phase: Double
    private let blue = Color(red: 41 / 255, green: 121 / 255, blue: 255 / 255)

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(white: 0.97))
            .frame(width: 96, height: 120)
            .overlay(
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate + phase
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let stretch = CGFloat(0.3 + 0.3 * (0.5 + 0.5 * sin(t * 1.8)))
                        let angle = Angle(radians: sin(t * 0.9) * 1.1)
                        let lookDirection = CGVector(dx: CGFloat(sin(t * 1.3) * 0.7),
                                                      dy: CGFloat(cos(t * 1.1) * 0.5))
                        DotRenderer.drawPlayer(context, center: center, radius: 22, color: blue,
                                                stretch: stretch, angle: angle,
                                                lookDirection: lookDirection, time: t)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}
