import SwiftUI

/// The "eat" effect: whatever gets eaten is pulled into the dot as a gooey
/// blob joined to it by a stretching neck (a metaball bridge), shrinking as
/// it goes until the dot swallows it. No particles, no rings, no glow.
enum MergeEffect {
    /// A smooth neck between two circles, or nil when they are too far apart
    /// (or one contains the other) for a bridge to make sense.
    /// Based on the classic metaball construction.
    static func bridge(from c1: CGPoint, _ r1: CGFloat, to c2: CGPoint, _ r2: CGFloat,
                       spread v: CGFloat = 0.5, handle: CGFloat = 2.4, maxDistance: CGFloat) -> Path? {
        let dx = c2.x - c1.x, dy = c2.y - c1.y
        let d = hypot(dx, dy)
        guard r1 > 0.5, r2 > 0.5, d > abs(r1 - r2) + 0.5, d < maxDistance else { return nil }

        var u1: CGFloat = 0, u2: CGFloat = 0
        if d < r1 + r2 {
            u1 = acos(min(1, max(-1, (r1 * r1 + d * d - r2 * r2) / (2 * r1 * d))))
            u2 = acos(min(1, max(-1, (r2 * r2 + d * d - r1 * r1) / (2 * r2 * d))))
        }
        let between = atan2(dy, dx)
        let maxSpread = acos(min(1, max(-1, (r1 - r2) / d)))
        let a1 = between + u1 + (maxSpread - u1) * v
        let a2 = between - u1 - (maxSpread - u1) * v
        let a3 = between + .pi - u2 - (.pi - u2 - maxSpread) * v
        let a4 = between - .pi + u2 + (.pi - u2 - maxSpread) * v

        func pt(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        let p1a = pt(c1, r1, a1), p1b = pt(c1, r1, a2), p2a = pt(c2, r2, a3), p2b = pt(c2, r2, a4)

        var d2 = min(v * handle, hypot(p1a.x - p2a.x, p1a.y - p2a.y) / (r1 + r2))
        d2 *= min(1, d * 2 / (r1 + r2))
        let h1 = r1 * d2, h2 = r2 * d2

        var path = Path()
        path.move(to: p1a)
        path.addCurve(to: p2a, control1: pt(p1a, h1, a1 - .pi / 2), control2: pt(p2a, h2, a3 + .pi / 2))
        path.addLine(to: p2b)
        path.addCurve(to: p1b, control1: pt(p2b, h2, a4 - .pi / 2), control2: pt(p1b, h1, a2 + .pi / 2))
        path.closeSubpath()
        return path
    }

    /// Draws one eaten thing being swallowed.
    /// - progress: 0 (just touched) ... 1 (gone)
    static func draw(_ context: GraphicsContext, progress: Double, eaten: CGPoint, eatenRadius: CGFloat,
                     eatenColor: Color, dot: CGPoint, dotRadius: CGFloat, dotColor: Color) {
        let t = CGFloat(min(1, max(0, progress)))
        // Slow at first (the neck stretches), then a quick gulp.
        let pull = t * t * (3 - 2 * t)
        let center = CGPoint(x: eaten.x + (dot.x - eaten.x) * pull, y: eaten.y + (dot.y - eaten.y) * pull)
        let radius = eatenRadius * (1 - 0.7 * t)
        let blend = eatenColor.mix(with: dotColor, amount: Double(t) * 0.8)

        if let neck = bridge(from: dot, dotRadius, to: center, radius, maxDistance: dotRadius + eatenRadius * 5 + 160) {
            context.fill(neck, with: .color(blend))
            context.stroke(neck, with: .color(blend.deepened(0.6)), lineWidth: max(1.4, radius * 0.1))
        }
        DotRenderer.draw(context, center: center, radius: radius, color: blend)
        // Draw the neck's fill again over the blob border where they join so
        // the two read as one continuous body.
        if let neck = bridge(from: dot, dotRadius, to: center, radius, maxDistance: dotRadius + eatenRadius * 5 + 160) {
            context.fill(neck, with: .color(blend))
        }
    }
}
