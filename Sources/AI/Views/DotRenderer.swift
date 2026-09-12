import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Draws every dot in the game — the player, collectibles, and ambient
/// wanderers — with one consistent, minimal glossy style: a flat fill plus a
/// soft top-right highlight, echoing the app's own dot logo. Keeping this in
/// one place is what makes §82's rule ("is the player still obviously a dot?")
/// easy to hold onto as more visual states get added later.
enum DotRenderer {
    static func draw(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, ringColor: Color? = nil, ringWidth: CGFloat = 0) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(color))

        // Soft sunlight-style highlight, top-right — same light direction as the app icon.
        let highlightCenter = CGPoint(x: center.x + radius * 0.35, y: center.y - radius * 0.35)
        let highlightRadius = radius * 0.5
        let highlightRect = CGRect(x: highlightCenter.x - highlightRadius, y: highlightCenter.y - highlightRadius,
                                    width: highlightRadius * 2, height: highlightRadius * 2)
        var highlightContext = context
        highlightContext.opacity = 0.35
        highlightContext.fill(Path(ellipseIn: highlightRect), with: .color(.white))

        if let ringColor, ringWidth > 0 {
            context.stroke(path, with: .color(ringColor), lineWidth: ringWidth)
        }
    }

    /// Whether the eyes show a black pupil (the in-game player, so it can
    /// visibly glance around) or stay plain white ovals (the main menu's
    /// preview dot, matching the app's own logo's clean blue dot).
    enum EyeStyle: Equatable {
        case withPupil
        case whiteOnly
    }

    /// Draws the player specifically: a squash-and-stretch deformed body (so
    /// motion reads as a bit more liquid/organic than a rigid circle sliding
    /// around) plus a simple pair of eyes that blink and glance toward
    /// wherever the player is heading. Collectibles/wanderers keep using the
    /// plain `draw` above — only the player gets this treatment, per §82's
    /// rule that the player is still obviously "a dot", just a lively one.
    ///
    /// - stretch: 0 (at rest, perfect circle) ... 1 (fully stretched along `angle`).
    /// - angle: current heading, only used while `stretch` > 0.
    /// - lookDirection: -1...1 per axis; where the pupils glance (ignored for `.whiteOnly`).
    /// - time: `Date().timeIntervalSinceReferenceDate`, drives the blink cycle.
    static func drawPlayer(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color,
                            stretch: CGFloat, angle: Angle, lookDirection: CGVector, time: Double,
                            eyeStyle: EyeStyle = .withPupil) {
        let clampedStretch = min(1, max(0, stretch))

        var bodyContext = context
        bodyContext.translateBy(x: center.x, y: center.y)
        bodyContext.rotate(by: angle)

        let halfWidth = radius * (1 + clampedStretch * 0.5)
        let halfHeight = radius * (1 - clampedStretch * 0.28)
        let bodyRect = CGRect(x: -halfWidth, y: -halfHeight, width: halfWidth * 2, height: halfHeight * 2)
        bodyContext.fill(Path(ellipseIn: bodyRect), with: .color(color))

        // Highlight stays sun-from-top-right relative to the (possibly
        // rotated) body, same light direction as every other dot.
        let highlightRadius = min(halfWidth, halfHeight) * 0.5
        let highlightCenter = CGPoint(x: halfWidth * 0.35, y: -halfHeight * 0.35)
        var highlightContext = bodyContext
        highlightContext.opacity = 0.35
        highlightContext.fill(
            Path(ellipseIn: CGRect(x: highlightCenter.x - highlightRadius, y: highlightCenter.y - highlightRadius,
                                    width: highlightRadius * 2, height: highlightRadius * 2)),
            with: .color(.white)
        )

        // Eyes are drawn in the ORIGINAL (unrotated) frame, centered on the
        // dot, so they always stay upright and just glance around instead of
        // tilting sideways whenever the body stretches/rotates with motion.
        drawEyes(context, center: center, radius: radius, lookDirection: lookDirection, time: time, style: eyeStyle)
    }

    private static func drawEyes(_ context: GraphicsContext, center: CGPoint, radius: CGFloat,
                                  lookDirection: CGVector, time: Double, style: EyeStyle) {
        let eyeSpacing = radius * 0.5
        let eyeRadius = radius * 0.26
        let pupilRadius = eyeRadius * 0.55
        let openAmount = blinkOpenAmount(time)
        let eyeY = center.y - radius * 0.08
        let sides: [CGFloat] = [-1, 1]

        for side in sides {
            let eyeCenter = CGPoint(x: center.x + side * eyeSpacing, y: eyeY)
            let scleraHalfHeight = max(eyeRadius * 0.12, eyeRadius * CGFloat(openAmount))
            let scleraRect = CGRect(x: eyeCenter.x - eyeRadius, y: eyeCenter.y - scleraHalfHeight,
                                     width: eyeRadius * 2, height: scleraHalfHeight * 2)
            context.fill(Path(ellipseIn: scleraRect), with: .color(.white))

            guard style == .withPupil, openAmount > 0.3 else { continue }
            let maxOffset = eyeRadius - pupilRadius
            let pupilCenter = CGPoint(
                x: eyeCenter.x + lookDirection.dx * maxOffset * 0.6,
                y: eyeCenter.y + lookDirection.dy * maxOffset * 0.6 * CGFloat(openAmount)
            )
            let pupilVisibleRadius = pupilRadius * CGFloat(openAmount)
            context.fill(
                Path(ellipseIn: CGRect(x: pupilCenter.x - pupilVisibleRadius, y: pupilCenter.y - pupilVisibleRadius,
                                        width: pupilVisibleRadius * 2, height: pupilVisibleRadius * 2)),
                with: .color(.black)
            )
        }
    }

    /// 1 = fully open, dipping to 0 for a brief moment once per cycle — a
    /// simple periodic blink rather than anything eye-tracking-accurate.
    private static func blinkOpenAmount(_ time: Double) -> Double {
        let period = 3.4
        let blinkDuration = 0.18
        let phase = time.truncatingRemainder(dividingBy: period)
        guard phase < blinkDuration else { return 1 }
        return 1 - sin(.pi * phase / blinkDuration)
    }

    /// Blends the neutral base dot color toward a form's color as progress climbs,
    /// per §5's "visual transformation" ladder (0% neutral → 100% full color).
    static func blendedPlayerColor(base: Color = Color(white: 0.16), formColor: Color?, progress: Double) -> Color {
        guard let formColor else { return base }
        let t = min(1, max(0, progress / 100))
        return base.mix(with: formColor, amount: t)
    }
}

extension Color {
    /// Simple linear RGB mix — good enough for the subtle transformation blend.
    func mix(with other: Color, amount: Double) -> Color {
        let t = min(1, max(0, amount))
        let (r1, g1, b1, a1) = components
        let (r2, g2, b2, a2) = other.components
        return Color(red: r1 + (r2 - r1) * t,
                      green: g1 + (g2 - g1) * t,
                      blue: b1 + (b2 - b1) * t,
                      opacity: a1 + (a2 - a1) * t)
    }

    private var components: (Double, Double, Double, Double) {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}
