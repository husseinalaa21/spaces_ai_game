import SwiftUI

/// The very first thing shown after tapping Play (§ new Play flow — replaces
/// the old one-time "This is you / Move / Eat it" tutorial entirely, and now
/// runs every single time Play is tapped instead of just once on first
/// launch): a plain white dot falling out of a pure black sky, settling with
/// a soft bounce, then a couple of short narrative lines — "That's you. A
/// dot, falling from the sky, looking for a space." then "Whatever you eat,
/// makes you." — before handing off to the shared 15-second practice room
/// (`RootView`'s `.practiceRound` phase).
///
/// § user feedback ("the dot in the waiting room should keep falling down as
/// animation"): the dot never actually comes to rest here anymore — instead
/// of falling once and settling in place while just breathing, it falls
/// continuously for as long as this screen is up, looping from just above
/// the top of the screen to just below the bottom over and over, via
/// `FallingDot` below (driven by `TimelineView(.animation)` so it's a true
/// per-frame animation, not a one-shot spring).
struct OnboardingView: View {
    let onFinished: () -> Void

    private enum Step { case falling, thatsYou, lookingForSpace, whateverYouEat }
    @State private var step: Step = .falling

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                FallingDot(width: geo.size.width, height: geo.size.height)

                VStack {
                    Spacer()
                    Text(caption)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 90)
                        .transition(.opacity)
                        .id(caption)
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear { runIntro() }
    }

    private var caption: String {
        switch step {
        case .falling: return ""
        case .thatsYou: return "That's you."
        case .lookingForSpace: return "A dot, falling from the sky, looking for a space."
        case .whateverYouEat: return "Whatever you eat, makes you."
        }
    }

    private func runIntro() {
        advance(to: .thatsYou, after: 0.9)
        advance(to: .lookingForSpace, after: 2.3)
        advance(to: .whateverYouEat, after: 4.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            onFinished()
        }
    }

    private func advance(to newStep: Step, after delay: Double, then extra: @escaping () -> Void = {}) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation { step = newStep }
            extra()
        }
    }
}

/// The beat between the 15-second practice room and the real final round
/// (§ new — "should have a dropping/loading page too") — the same
/// falling-dot moment as the very first intro above, but landing on a fixed
/// congratulatory line instead of the narrative sequence, since the player
/// already knows what a dot falling into a space means by the time they see
/// this one. `RootView`'s `.levelTransition` phase shows this, then starts
/// the final round once `onFinished` fires.
struct LevelTransitionView: View {
    var message: String = "Congratulations! You moved to the next level — the Final Universe."
    let onFinished: () -> Void

    @State private var showMessage = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                FallingDot(width: geo.size.width, height: geo.size.height)

                VStack {
                    Spacer()
                    if showMessage {
                        Text(message)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                            .padding(.bottom, 90)
                            .transition(.opacity)
                    }
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear { runTransition() }
    }

    private func runTransition() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation { showMessage = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            onFinished()
        }
    }
}

/// A plain white dot that falls once and settles in the middle of the
/// screen — used by both `OnboardingView` and `LevelTransitionView`
/// (§ user feedback: "the falling should stop in the middle... as
/// animation" — back to landing and staying put rather than looping
/// forever, but with a better-looking fall this time). While it's dropping,
/// the shape itself stretches — the top trailing upward like a comet, the
/// bottom edge anchored where it's headed — instead of staying a rigid
/// circle the whole way down, then does one small squash "splat" on
/// landing before settling into a soft idle breathe. Driven entirely off
/// `TimelineView(.animation)` plus a fixed `startDate` captured on first
/// appearance, so the whole fall is a pure function of elapsed time rather
/// than a black-box spring.
private struct FallingDot: View {
    let width: CGFloat
    let height: CGFloat

    /// Time from release to touching down at `restY`.
    private let fallDuration: Double = 0.85
    /// A brief squash pulse right after landing, before it's fully at rest.
    private let bounceDuration: Double = 0.45
    private let startY: Double = -80

    @State private var startDate = Date()

    private var restY: Double { Double(height) * 0.42 }

    var body: some View {
        TimelineView(.animation) { timeline in
            dotView(at: timeline.date)
        }
    }

    // Pulled out of the TimelineView closure with an explicit return type —
    // a closure with this many intermediate `let`/`var` computations before
    // its final View made the compiler unable to infer TimelineView's
    // `Content` generic parameter on its own.
    private func dotView(at date: Date) -> some View {
        let elapsed = date.timeIntervalSince(startDate)

        // Position: an easing-out drop so it settles softly instead of
        // slamming into restY.
        let fallX = min(1, max(0, elapsed / fallDuration))
        let easedFall = 1 - pow(1 - fallX, 3)
        let y = startY + (restY - startY) * easedFall

        // Shape: stretched tall (and slightly narrower) at peak speed,
        // mid-fall, easing back to a perfect circle exactly as it
        // touches down — anchored at the bottom so the extra length
        // trails upward, like the dot is being pulled up behind itself.
        let speedProxy = sin(Double.pi * fallX)
        var stretchY = 1 + 0.32 * speedProxy
        var squashX = 1 - 0.16 * speedProxy

        // Landing: one quick squash-wide/flatten pulse right after
        // touchdown, fading out, before it's fully at rest.
        if elapsed > fallDuration {
            let bounceX = min(1, max(0, (elapsed - fallDuration) / bounceDuration))
            let pulse = sin(Double.pi * bounceX) * (1 - bounceX)
            stretchY = 1 - 0.14 * pulse
            squashX = 1 + 0.09 * pulse
        }

        // Idle: a slow, gentle breathing pulse once it's fully settled.
        let settleElapsed = elapsed - fallDuration - bounceDuration
        let idle = settleElapsed > 0 ? 1 + 0.04 * sin(settleElapsed * 2.2) : 1

        return Circle()
            .fill(Color.white)
            .frame(width: 64, height: 64)
            .scaleEffect(x: CGFloat(squashX * idle), y: CGFloat(stretchY * idle), anchor: .bottom)
            .shadow(color: .white.opacity(0.35), radius: 26)
            .position(x: width / 2, y: CGFloat(y))
    }
}
