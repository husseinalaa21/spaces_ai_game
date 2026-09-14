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
        /// True only for `finalUniverse` below — gates the nebula clouds and
        /// starfield in `draw`, since every other palette is a plain flat
        /// world and shouldn't pay for (or show) that extra layer.
        var isCosmic: Bool = false
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

    /// AI+ premium White Space re-skins (`UniverseTheme.sunset`/`.midnight`) —
    /// same grid, same world, just a different look, per §38's "cosmetics
    /// only" monetization rule.
    static let sunset = Palette(
        background: Color(red: 1.0, green: 0.95, blue: 0.90),
        line: Color(red: 0.95, green: 0.55, blue: 0.35).opacity(0.55)
    )

    static let midnight = Palette(
        background: Color(red: 0.07, green: 0.08, blue: 0.14),
        line: Color.white.opacity(0.12)
    )

    /// The larger buyable Universe catalog (§ new — "add more universes to
    /// buy"), each still just a background/grid recolor per §38's
    /// "cosmetics only" rule. `aurora` and `cosmic` opt into the same
    /// nebula-cloud + starfield treatment as `finalUniverse` below (via
    /// `isCosmic`) since both are meant to read as genuinely "in space".
    static let ocean = Palette(
        background: Color(red: 0.86, green: 0.94, blue: 1.0),
        line: Color(red: 0.20, green: 0.50, blue: 0.80).opacity(0.5)
    )

    static let forest = Palette(
        background: Color(red: 0.90, green: 0.96, blue: 0.89),
        line: Color(red: 0.22, green: 0.52, blue: 0.26).opacity(0.5)
    )

    static let bubblegum = Palette(
        background: Color(red: 1.0, green: 0.90, blue: 0.95),
        line: Color(red: 0.92, green: 0.40, blue: 0.65).opacity(0.5)
    )

    static let volcano = Palette(
        background: Color(red: 0.10, green: 0.04, blue: 0.03),
        line: Color(red: 0.95, green: 0.35, blue: 0.10).opacity(0.55)
    )

    static let aurora = Palette(
        background: Color(red: 0.03, green: 0.07, blue: 0.09),
        line: Color(red: 0.30, green: 0.90, blue: 0.70).opacity(0.45),
        isCosmic: true
    )

    static let cosmic = Palette(
        background: Color(red: 0.03, green: 0.02, blue: 0.09),
        line: Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.4),
        isCosmic: true
    )

    /// The final room's own look (§ new two-phase Play flow — "when the time
    /// is done it should change the universe... something like Nebulous.io"):
    /// deliberately not one of the cosmetic Universe picks above, so arriving
    /// here after the practice room actually reads as a real place change —
    /// a dark, glowing nebula field instead of another flat palette swap.
    static let finalUniverse = Palette(
        background: Color(red: 0.02, green: 0.02, blue: 0.06),
        line: Color.white.opacity(0.09),
        isCosmic: true
    )

    static func palette(for theme: UniverseTheme) -> Palette {
        switch theme {
        case .white: return whiteSpace
        case .sunset: return sunset
        case .midnight: return midnight
        case .ocean: return ocean
        case .forest: return forest
        case .bubblegum: return bubblegum
        case .volcano: return volcano
        case .aurora: return aurora
        case .cosmic: return cosmic
        }
    }

    static let cellSize: CGFloat = 60
    static let lineWidth: CGFloat = 1.2

    /// Faint subdivisions inside each main cell — purely decorative texture
    /// so the world reads as a bit more alive/dynamic than one flat sheet.
    static let fineDivisions = 3
    static let fineLineWidth: CGFloat = 0.6

    static func draw(_ context: GraphicsContext, screenSize: CGSize, cameraOffset: CGPoint, palette: Palette,
                      reduceMotion: Bool = false) {
        context.fill(Path(CGRect(origin: .zero, size: screenSize)), with: .color(palette.background))

        // Soft glowing nebula clouds and a distant starfield — only the
        // final room's palette turns this on (§ Nebulous.io-style reference)
        // — drawn in world space like the grid below so they scroll with the
        // camera instead of feeling like a flat sticker over the screen.
        if palette.isCosmic {
            drawNebula(context, screenSize: screenSize, cameraOffset: cameraOffset)
            drawStars(context, screenSize: screenSize, cameraOffset: cameraOffset)
        }

        // A very slow, faint breathing on just the fine subdivisions — never
        // the main grid, which stays crisp and stable for readability — so
        // the world itself feels quietly alive rather than one static sheet
        // sitting behind everything that actually moves. Both grids dialed
        // back further (§ user feedback: the grid boxes read as too visible)
        // — same lines, just quieter, so they still give a sense of scale
        // and motion without competing with gameplay on top of them.
        let breathe = reduceMotion ? 1.0 : 1.0 + 0.35 * sin(Date().timeIntervalSinceReferenceDate * 0.4)
        drawGrid(context, screenSize: screenSize, cameraOffset: cameraOffset,
                  cellSize: cellSize / CGFloat(fineDivisions), color: palette.line.opacity(0.18 * breathe), lineWidth: fineLineWidth)
        drawGrid(context, screenSize: screenSize, cameraOffset: cameraOffset,
                  cellSize: cellSize, color: palette.line.opacity(0.5), lineWidth: lineWidth)

        // A soft vignette — screen-space, not world-space, so it always
        // frames the viewport itself rather than scrolling with the camera —
        // darkening gently toward the edges/corners (§ user feedback: "a
        // graduate black around it") for a bit of depth and focus instead of
        // one flat, evenly-lit sheet.
        drawVignette(context, screenSize: screenSize)
    }

    /// A radial gradient, clear in the middle and easing to a soft black
    /// toward the corners, drawn last so it sits over the grid and everything
    /// else already composited beneath it in `WhiteSpaceView`.
    private static func drawVignette(_ context: GraphicsContext, screenSize: CGSize) {
        let center = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        let maxRadius = sqrt(pow(screenSize.width / 2, 2) + pow(screenSize.height / 2, 2))
        context.fill(
            Path(CGRect(origin: .zero, size: screenSize)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.55),
                    .init(color: .black.opacity(0.30), location: 1.0)
                ]),
                center: center, startRadius: maxRadius * 0.35, endRadius: maxRadius
            )
        )
    }

    /// A handful of big, soft, blurred color clouds parked at fixed spots
    /// around the world — the "nebula" half of the final room's Nebulous.io-
    /// style look. Fixed world positions (not random per-frame) so they read
    /// as actual landmarks in the space rather than shifting noise.
    private static let nebulaBlobs: [(x: CGFloat, y: CGFloat, radius: CGFloat, color: Color)] = [
        (600, 500, 420, Color(red: 0.45, green: 0.22, blue: 0.62)),
        (3200, 850, 500, Color(red: 0.14, green: 0.34, blue: 0.58)),
        (1800, 2600, 460, Color(red: 0.55, green: 0.18, blue: 0.42)),
        (3400, 3300, 380, Color(red: 0.16, green: 0.46, blue: 0.50)),
        (900, 3500, 400, Color(red: 0.34, green: 0.20, blue: 0.60)),
        (2600, 1650, 360, Color(red: 0.18, green: 0.28, blue: 0.62)),
        (2000, 200, 340, Color(red: 0.50, green: 0.24, blue: 0.30))
    ]

    private static func drawNebula(_ context: GraphicsContext, screenSize: CGSize, cameraOffset: CGPoint) {
        for blob in nebulaBlobs {
            let sx = blob.x - cameraOffset.x
            let sy = blob.y - cameraOffset.y
            guard sx > -blob.radius, sx < screenSize.width + blob.radius,
                  sy > -blob.radius, sy < screenSize.height + blob.radius else { continue }
            var blobContext = context
            blobContext.opacity = 0.4
            blobContext.addFilter(.blur(radius: blob.radius * 0.35))
            blobContext.fill(
                Path(ellipseIn: CGRect(x: sx - blob.radius, y: sy - blob.radius,
                                        width: blob.radius * 2, height: blob.radius * 2)),
                with: .color(blob.color)
            )
        }
    }

    /// A dense but cheap starfield covering the whole world, built the same
    /// way as `drawGrid` below — walk only the cells currently on screen —
    /// but instead of a line per cell, each cell deterministically hashes to
    /// either zero or one star, so the same patch of space always shows the
    /// same stars instead of them flickering as the camera passes over.
    private static let starCellSize: CGFloat = 130

    private static func drawStars(_ context: GraphicsContext, screenSize: CGSize, cameraOffset: CGPoint) {
        let cell = starCellSize
        let startCol = Int((cameraOffset.x / cell).rounded(.down)) - 1
        let endCol = Int(((cameraOffset.x + screenSize.width) / cell).rounded(.up)) + 1
        let startRow = Int((cameraOffset.y / cell).rounded(.down)) - 1
        let endRow = Int(((cameraOffset.y + screenSize.height) / cell).rounded(.up)) + 1
        guard startCol <= endCol, startRow <= endRow else { return }
        let t = Date().timeIntervalSinceReferenceDate

        for col in startCol...endCol {
            for row in startRow...endRow {
                let seed = Double(col) * 92.17 + Double(row) * 51.73 + 7.0
                let hash = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                guard hash < 0.55 else { continue }
                let localX = abs(sin(seed * 1.7)).truncatingRemainder(dividingBy: 1)
                let localY = abs(cos(seed * 2.3)).truncatingRemainder(dividingBy: 1)
                let worldX = (CGFloat(col) + CGFloat(localX)) * cell
                let worldY = (CGFloat(row) + CGFloat(localY)) * cell
                let sx = worldX - cameraOffset.x
                let sy = worldY - cameraOffset.y
                guard sx > -6, sx < screenSize.width + 6, sy > -6, sy < screenSize.height + 6 else { continue }
                let twinkle = 0.35 + 0.45 * abs(sin(t * 1.4 + seed))
                let r: CGFloat = hash < 0.12 ? 1.8 : 1.0
                context.fill(
                    Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(twinkle))
                )
            }
        }
    }

    private static func drawGrid(_ context: GraphicsContext, screenSize: CGSize, cameraOffset: CGPoint,
                                  cellSize: CGFloat, color: Color, lineWidth: CGFloat) {
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
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }
}
