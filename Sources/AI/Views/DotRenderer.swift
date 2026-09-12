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
