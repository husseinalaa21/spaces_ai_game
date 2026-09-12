import SwiftUI

/// The shared "window pane" grid background used behind both worlds, so
/// White Space and (eventually) Dark Space share one visual language — the
/// same grid used in the app's own dot logo, just recolored per world.
///
/// The grid is drawn in *world* coordinates (not screen coordinates), so it
/// scrolls with the camera exactly like everything else instead of looking
/// like a static screen-space overlay.
enum WorldBackground {
    struct Palette {
        let background: Color
        let line: Color
    }

    static let whiteSpace = Palette(
        background: .white,
        line: Color(red: 222/255, green: 224/255, blue: 228/255)
    )

    /// Placeholder palette for Dark Space (§81: near-black background, light
    /// grid lines) — not wired to a playable screen yet, but ready for when
    /// Phase 4 adds one.
    static let darkSpace = Palette(
        background: Color(red: 6/255, green: 6/255, blue: 8/255),
        line: Color(red: 40/255, green: 42/255, blue: 48/255)
    )

    static let cellSize: CGFloat = 60
    static let lineWidth: CGFloat = 1.2

    static func draw(_ context: GraphicsContext, screenSize: CGSize, cameraOffset: CGPoint, palette: Palette) {
        context.fill(Path(CGRect(origin: .zero, size: screenSize)), with: .color(palette.background))

        let startX = (cameraOffset.x / cellSize).rounded(.down) * cellSize
        let startY = (cameraOffset.y / cellSize).rounded(.down) * cellSize

        var path = Path()
        var x = startX
        while x - cameraOffset.x <= screenSize.width {
            let sx = x - cameraOffset.x
            path.move(to: CGPoint(x: sx, y: 0))
            path.addLine(to: CGPoint(x: sx, y: screenSize.height))
            x += cellSize
        }
        var y = startY
        while y - cameraOffset.y <= screenSize.height {
            let sy = y - cameraOffset.y
            path.move(to: CGPoint(x: 0, y: sy))
            path.addLine(to: CGPoint(x: screenSize.width, y: sy))
            y += cellSize
        }
        context.stroke(path, with: .color(palette.line), lineWidth: lineWidth)
    }
}
