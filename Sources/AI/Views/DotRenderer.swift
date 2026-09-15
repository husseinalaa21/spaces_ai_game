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
    /// - eatPulse: 0...1, briefly raised right after eating something (see
    ///   `WhiteSpaceView`'s arrival flash) to richen the self-colored border below.
    /// - dotStyle: the player's chosen cosmetic material (§28/§29's Premium
    ///   Dots — picked on the main menu) — a tint/shine layered on top of the
    ///   transformation color, never replacing it.
    static func drawPlayer(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color,
                            stretch: CGFloat, angle: Angle, lookDirection: CGVector, time: Double,
                            eyeStyle: EyeStyle = .withPupil, reduceMotion: Bool = false, eatPulse: Double = 0,
                            dotStyle: DotStyle = .classic, customDot: CustomDot? = nil) {
        // `stretch` is driven by a slightly underdamped spring on the caller
        // side (see `WhiteSpaceView.updateStretch`), so it can overshoot a
        // touch past 1 for a bit of jelly pop — clamp the *shape* math to a
        // sane range while still letting a little of that overshoot read on
        // the tail.
        let s = min(1.2, max(0, stretch))
        let shapeStretch = min(1, s)

        // A continuous, always-on ripple so the body's outline keeps subtly
        // reshaping itself throughout play — not just while dragging — like
        // a liquid blob that never quite sits still. Each side of the dot
        // wobbles on its own out-of-phase sine pair so the whole silhouette
        // keeps shifting asymmetrically rather than just breathing in and
        // out uniformly. Skipped under Reduce Motion, which is exactly the
        // kind of gratuitous, autonomous motion that setting is meant to cut.
        func wobble(_ freqA: Double, _ freqB: Double, _ phase: Double) -> CGFloat {
            guard !reduceMotion else { return 0 }
            // Tapers down while the body is actively stretched from real
            // movement (`shapeStretch` high) — § user feedback: "the moving
            // shape of the dot... should be much better and more
            // professional" — so a dot in motion reads as one clean,
            // intentional squash-and-stretch instead of the idle ripple's
            // own noise competing with it. The ripple is still in full
            // effect at rest — just fades out as real motion takes over —
            // and amplitude itself is a touch calmer than before too.
            let taper = 1 - shapeStretch * 0.75
            return CGFloat((sin(time * freqA + phase) * 0.07 + sin(time * freqB + phase * 1.7) * 0.035) * taper)
        }
        let frontWobble = wobble(1.1, 2.6, 0.0)
        let backWobble = wobble(0.9, 2.1, 2.1)
        let topWobble = wobble(1.4, 2.9, 4.2)
        let bottomWobble = wobble(1.2, 2.4, 1.1)
        // Kept for the body proportions below, which only want a coarse sense of how
        // deformed the body currently is, not the per-side detail above.
        let idleWobble = (frontWobble + backWobble + topWobble + bottomWobble) / 4

        // Raised briefly right after eating something (see `WhiteSpaceView`'s
        // arrival flash) to richen the glow/highlight below — computed early
        // since the new ambient glow (drawn before the body itself) needs it too.
        let pulse = max(0, min(1, eatPulse))


        // The cosmetic dot style (§28/§29, now a much bigger catalog — see
        // `DotStyle.visual`) tints the base transformation color and
        // richens the shine a little — it never replaces the color itself,
        // so the dot still tells you what you're becoming. Rainbow's accent
        // cycles hue over time instead of staying fixed; everything else
        // uses its own fixed accent. Computed before the body itself so the
        // ambient glow just below (drawn in world space, behind the body)
        // can already use it.
        // A custom dot replaces the catalog style outright — its own base
        // colour, no accent tint, and none of the style's worn items, which
        // would otherwise sit on top of the player's own artwork.
        let visual = customDot == nil ? dotStyle.visual : DotStyle.classic.visual
        let effectiveAccent: Color
        if visual.hasRainbow {
            let hue = (time / 5.0).truncatingRemainder(dividingBy: 1.0)
            effectiveAccent = Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.85, brightness: 1.0)
        } else {
            effectiveAccent = visual.accentColor
        }
        let baseColor = customDot?.baseColor.color ?? color
        let styledColor = visual.mixAmount > 0 ? baseColor.mix(with: effectiveAccent, amount: visual.mixAmount) : baseColor
        let styleShine = visual.shine

        // A two-layer ambient bloom bleeding out into the space around the
        // dot instead of one flat blurred circle — a big, very soft outer
        // glow for atmosphere plus a tighter, brighter inner glow right at
        // the edge for a proper "light source" falloff — brighter for
        // shinier/premium styles and right after eating (§ user feedback:
        // "make the light effect much better and more professional").
        // Drawn in plain world space (glows are round either way, no need
        // for the body's own rotation) before anything else so it sits
        // fully behind the dot rather than washing out its edges.
        do {
            let outerRadius = radius * (1.9 + 0.45 * pulse + 0.6 * styleShine)
            var outerGlow = context
            outerGlow.opacity = 0.10 + 0.09 * styleShine + 0.12 * pulse
            outerGlow.addFilter(.blur(radius: radius * 0.85))
            outerGlow.fill(
                Path(ellipseIn: CGRect(x: center.x - outerRadius, y: center.y - outerRadius,
                                        width: outerRadius * 2, height: outerRadius * 2)),
                with: .color(styledColor)
            )

            let innerRadius = radius * (1.25 + 0.2 * pulse + 0.3 * styleShine)
            var innerGlow = context
            innerGlow.opacity = 0.16 + 0.16 * styleShine + 0.2 * pulse
            innerGlow.addFilter(.blur(radius: radius * 0.32))
            innerGlow.fill(
                Path(ellipseIn: CGRect(x: center.x - innerRadius, y: center.y - innerRadius,
                                        width: innerRadius * 2, height: innerRadius * 2)),
                with: .color(styledColor.mix(with: .white, amount: 0.2))
            )
        }

        var bodyContext = context
        bodyContext.translateBy(x: center.x, y: center.y)
        bodyContext.rotate(by: angle)

        // The leading edge (direction of travel) rounds out a little; the
        // back stretches further and tapers — reads as a smooth water
        // droplet in motion rather than a plain squashed ellipse (or a sharp
        // spike). At rest (`stretch` 0) this settles down to just the
        // continuous ripple above, rather than a perfectly static circle.
        let front = radius * (1 + shapeStretch * 0.22 + frontWobble)
        let back = radius * (1 + shapeStretch * (0.85 + max(0, s - 1) * 1.2) + backWobble)
        let top = radius * (1 - shapeStretch * 0.3 + topWobble)
        let bottom = radius * (1 - shapeStretch * 0.3 + bottomWobble)
        let tailKappa: CGFloat = 0.5523 * (1 - shapeStretch * 0.4)

        let bodyPath = blobOutline(front: front, back: back, top: top, bottom: bottom, tailKappa: tailKappa)

        // A glossy radial gradient — lighter toward the sunlit corner,
        // richer/darker toward the far edge — instead of a flat fill, for a
        // polished, dimensional "droplet" look rather than a flat cartoon
        // disc. A four-stop ramp (§ user feedback: "make the light effect
        // much better and more professional") gives a smoother, more
        // physically-lit falloff than a plain three-color blend — an extra
        // near-white hotspot right at the light source, and an extra
        // mid-tone step before the darkest edge, instead of jumping straight
        // from the base color to black.
        let lightShade = styledColor.mix(with: .white, amount: 0.5 + styleShine)
        let hotspotShade = styledColor.mix(with: .white, amount: 0.75 + styleShine * 0.6)
        let midShade = styledColor.mix(with: .black, amount: 0.08)
        let darkShade = styledColor.mix(with: .black, amount: 0.3)
        let gradientCenter = CGPoint(x: front * 0.32, y: -top * 0.34)
        let gradientRadius = max(front, back, top, bottom) * 1.2
        bodyContext.fill(
            bodyPath,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: hotspotShade, location: 0.0),
                    .init(color: lightShade, location: 0.22),
                    .init(color: styledColor, location: 0.5),
                    .init(color: midShade, location: 0.78),
                    .init(color: darkShade, location: 1.0)
                ]),
                center: gradientCenter, startRadius: 0, endRadius: gradientRadius
            )
        )

        // A small, subtle inner border (§ user feedback: "add a small border
        // to the dot inside") — a thin rim just inside the body's own edge,
        // not a halo drawn around it like the aura that got removed earlier.
        // Clipping to the body path first and stroking at double the visible
        // width means only the inner half of that stroke actually shows, so
        // it reads as sitting inside the dot rather than bleeding past its
        // silhouette.
        let borderWidth = max(1, radius * 0.035)
        var borderContext = bodyContext
        borderContext.clip(to: bodyPath)
        borderContext.stroke(bodyPath, with: .color(darkShade.opacity(0.4)), lineWidth: borderWidth * 2)

        // A soft, blurred highlight instead of a hard-edged circle — same
        // sun-from-top-right direction as every other dot in the game — for
        // the final glossy touch.
        let highlightRadius = min(front, top) * 0.42
        let highlightCenter = CGPoint(x: front * 0.32, y: -top * 0.38)
        // This highlight itself briefly brightens right after eating
        // (`eatPulse`) on top of the thin inner border added just above.
        var highlightContext = bodyContext
        highlightContext.opacity = 0.5 + 0.3 * pulse
        highlightContext.addFilter(.blur(radius: highlightRadius * 0.35))
        highlightContext.fill(
            Path(ellipseIn: CGRect(x: highlightCenter.x - highlightRadius, y: highlightCenter.y - highlightRadius,
                                    width: highlightRadius * 2, height: highlightRadius * 2)),
            with: .color(.white)
        )

        // A small, sharp specular hotspot layered on top of the soft blurred
        // highlight above — the classic "wet glass" catch-light that reads
        // as an actual light source reflecting off a glossy surface, rather
        // than just a diffuse glow (§ user feedback: "the light effect
        // should be much better").
        let specRadius = highlightRadius * 0.3
        let specCenter = CGPoint(x: highlightCenter.x - highlightRadius * 0.2, y: highlightCenter.y - highlightRadius * 0.2)
        var specContext = bodyContext
        specContext.opacity = 0.8 + 0.2 * pulse
        specContext.fill(
            Path(ellipseIn: CGRect(x: specCenter.x - specRadius, y: specCenter.y - specRadius,
                                    width: specRadius * 2, height: specRadius * 2)),
            with: .color(.white)
        )

        // A tiny, fully-opaque pinpoint sparkle right at the peak of the
        // specular hotspot — the last bit of "polish" a professional glossy
        // render adds on top of a soft highlight (§ user feedback: "make the
        // light effect much better and more professional").
        let pinRadius = specRadius * 0.32
        let pinCenter = CGPoint(x: specCenter.x - specRadius * 0.15, y: specCenter.y - specRadius * 0.15)
        bodyContext.fill(
            Path(ellipseIn: CGRect(x: pinCenter.x - pinRadius, y: pinCenter.y - pinRadius,
                                    width: pinRadius * 2, height: pinRadius * 2)),
            with: .color(.white)
        )

        // A crisp light-catching rim traced exactly along the body's own
        // current silhouette — trimming the front→top curve segment, the
        // same quarter the gradient/highlight above already treat as facing
        // the light — instead of a hand-placed blurred ellipse, so it hugs
        // the true outline through every squash/stretch/wobble frame.
        let litRim = bodyPath.trimmedPath(from: 0.03, to: 0.22)
        var litRimContext = bodyContext
        litRimContext.opacity = 0.55 + 0.35 * pulse
        litRimContext.addFilter(.blur(radius: max(0.4, radius * 0.025)))
        litRimContext.stroke(litRim, with: .color(.white), style: StrokeStyle(lineWidth: max(1, radius * 0.07), lineCap: .round))

        // No dark shadow rim on the body (§ new — "remove the shadow
        // behind the dots"): the dot reads as a flat, bright shape lit only
        // by its own highlight.

        // A slow inner sheen — a soft light band drifting back-to-front
        // across the body every few seconds, clipped to the outline — gives
        // the dot a "playing"/living-liquid feel even while standing
        // perfectly still, on top of the squash/stretch ripple above.
        // Applies to every style (Galaxy's stars, drawn next, layer on top).
        if !reduceMotion {
            let sweepPeriod = 3.6
            let sweepPhase = (time.truncatingRemainder(dividingBy: sweepPeriod)) / sweepPeriod
            let sweepOpacity = 0.10 * max(0, sin(.pi * sweepPhase))
            if sweepOpacity > 0.003 {
                let travel = front + back
                let sweepX = -back + travel * CGFloat(sweepPhase) * 1.15
                var sweepContext = bodyContext
                sweepContext.clip(to: bodyPath)
                sweepContext.opacity = sweepOpacity
                sweepContext.addFilter(.blur(radius: radius * 0.3))
                let sweepWidth = radius * 0.4
                let sweepHeight = (top + bottom) * 1.3
                sweepContext.fill(
                    Path(ellipseIn: CGRect(x: sweepX - sweepWidth / 2, y: -sweepHeight / 2,
                                            width: sweepWidth, height: sweepHeight)),
                    with: .color(.white)
                )
            }
        }

        // Galaxy/Nebula's signature per §29: a few tiny twinkling stars
        // clipped to the body outline, rather than a plain tinted fill like
        // the other premium styles.
        if visual.hasStars {
            var starContext = bodyContext
            starContext.clip(to: bodyPath)
            let starSpots: [(CGFloat, CGFloat, Double)] = [
                (front * 0.05, -top * 0.45, 0.0),
                (-back * 0.35, top * 0.15, 1.3),
                (front * 0.4, bottom * 0.35, 2.6),
                (-back * 0.1, -top * 0.05, 4.0),
                (front * 0.15, bottom * 0.55, 5.3)
            ]
            for (sx, sy, seedPhase) in starSpots {
                let twinkle = 0.35 + 0.55 * max(0, sin(time * 2.2 + seedPhase))
                var starDotContext = starContext
                starDotContext.opacity = twinkle
                let r = radius * 0.035
                starDotContext.fill(
                    Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)),
                    with: .color(.white)
                )
            }
        }

        // Eyes now live INSIDE the body's own rotated + stretched local frame
        // (`bodyContext`), anchored to one fixed spot near the front/top —
        // instead of a separate overlay redrawn upright in world space every
        // frame — so they visibly shift with the current squash/stretch
        // shape and turn together with the body's direction of travel. That
        // reads as the eyes actually being part of the dot's liquid surface,
        // not a flat sticker floating on top of it that ignores how the body
        // underneath is currently moving or deformed.
        let eyeAnchor = CGPoint(x: front * 0.08, y: -top * 0.18)
        let eyeScale = min(front, top)
        // `lookDirection` arrives in world space (screen up/down, travel
        // direction); rotate it into the body's own local frame (inverse of
        // the rotation just applied to `bodyContext`) so an idle "glance up"
        // still reads as up from the dot's own point of view once the whole
        // body has turned to face some direction.
        let theta = angle.radians
        let cosT = CGFloat(cos(theta)), sinT = CGFloat(sin(theta))
        let localLook = CGVector(dx: lookDirection.dx * cosT + lookDirection.dy * sinT,
                                  dy: -lookDirection.dx * sinT + lookDirection.dy * cosT)
        // The player's own artwork, clipped to the body and drawn in the same
        // local frame as everything else, so it squashes, stretches and turns
        // with the dot rather than floating flat on top of it. Drawn under
        // the eyes so painting over them never blinds the dot.
        if let customDot {
            drawCustomArt(bodyContext, radius: radius, customDot: customDot, bodyPath: bodyPath)
        }

        drawEyes(bodyContext, anchor: eyeAnchor, scale: eyeScale, lookDirection: localLook, time: time, style: eyeStyle)

        // Worn over the eyes, in the same local frame, so it squashes and
        // turns with the body instead of floating on top of it.
        drawEyeWear(bodyContext, anchor: eyeAnchor, scale: eyeScale,
                    kind: customDot == nil ? visual.eyeWear : .none,
                    tint: styledColor.wornAccent(hueShift: 0.5))

        // A second worn item below the hat (§ new — "more cloths": a bowtie,
        // scarf, collar, cape, or medal per style — see `DotStyle.Accessory`)
        // — a simple drawn vector shape rather than another SF Symbol, so it
        // clearly reads as something worn low on the body rather than a
        // second badge stacked on the head. Tinted with its own colour a third
        // of the way round the wheel from the body (§ new — worn items should
        // read as clothing, not as a shaded part of the dot), which also keeps
        // it distinct from the hat's own accent just below.
        drawAccessory(bodyContext, front: front, back: back, top: top, bottom: bottom,
                      kind: customDot == nil ? visual.accessory : .none,
                      tint: styledColor.wornAccent(hueShift: 0.34),
                      bodyPath: bodyPath)

        // A small worn accessory for premium Dot Styles (§ new — user asked
        // for something like "wearing a hat" so a premium pick reads at a
        // glance, not just through a tinted body): drawn last, perched right
        // on top of the head, in the same rotated/stretched local frame as
        // everything else above so it rides along with the body's motion.
        // Real SF Symbols glyphs (§ user feedback: hand-drawn shapes didn't
        // read right — "look up in the libraries", i.e. the system icon set
        // already used elsewhere in this app, like the Store's pack icons)
        // rather than custom vector paths, tinted with the hue opposite the
        // body's (§ new — "make their colors different than the dots") so the
        // hat reads as a worn object rather than part of the dot. `.classic`
        // gets nothing.
        drawHat(bodyContext, top: top, hatSymbol: customDot == nil ? visual.hatSymbol : nil,
                tint: styledColor.wornAccent(hueShift: 0.5))
    }

    /// Paints a `CustomDot`'s strokes and stickers.
    ///
    /// Coordinates arrive normalized to the radius (see `DotStroke`), so this
    /// is the single place that converts them to points — which is what lets
    /// the same artwork render identically at 46pt in the picker and at full
    /// size in the game.
    ///
    /// `bodyPath` clips everything: paint that ran past the edge in the
    /// studio stays inside the dot here too, at any squash or stretch.
    static func drawCustomArt(_ context: GraphicsContext, radius: CGFloat,
                              customDot: CustomDot, bodyPath: Path) {
        guard !customDot.isBlank else { return }
        var art = context
        art.clip(to: bodyPath)

        for stroke in customDot.strokes {
            guard let first = stroke.points.first else { continue }
            let width = max(0.5, CGFloat(stroke.width) * radius)
            if stroke.points.count == 1 {
                // A single tap is a dot of paint, not a zero-length line —
                // stroking a one-point path draws nothing at all.
                let r = width / 2
                art.fill(
                    Path(ellipseIn: CGRect(x: first.x * radius - r, y: first.y * radius - r,
                                            width: r * 2, height: r * 2)),
                    with: .color(stroke.color.color)
                )
                continue
            }
            var path = Path()
            path.move(to: CGPoint(x: first.x * radius, y: first.y * radius))
            for point in stroke.points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * radius, y: point.y * radius))
            }
            art.stroke(path, with: .color(stroke.color.color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }

        for sticker in customDot.stickers {
            let size = max(1, CGFloat(sticker.scale) * radius)
            let glyph = Text(Image(systemName: sticker.symbol))
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(sticker.color.color)
            art.draw(glyph, at: CGPoint(x: sticker.position.x * radius,
                                        y: sticker.position.y * radius))
        }
    }

    /// Eyewear worn over the eyes (§ new — "replace their eyes with glasses
    /// or something for some of them"). Proportions mirror `drawEyes` so the
    /// lenses land on the eyes at any body size.
    private static func drawEyeWear(_ context: GraphicsContext, anchor: CGPoint, scale: CGFloat,
                                     kind: DotStyle.EyeWear, tint: Color) {
        guard kind != .none else { return }
        let spacing = scale * 0.22
        let lensR = scale * 0.19
        let line = max(0.6, scale * 0.032)
        let left = CGPoint(x: anchor.x - spacing, y: anchor.y)
        let right = CGPoint(x: anchor.x + spacing, y: anchor.y)
        let dark = Color.black.opacity(0.78)

        func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        /// A short white streak across a lens — the one cue that reads as
        /// "glass" rather than a flat hole.
        func glint(_ c: CGPoint, _ r: CGFloat) {
            var g = Path()
            g.move(to: CGPoint(x: c.x - r * 0.45, y: c.y + r * 0.2))
            g.addLine(to: CGPoint(x: c.x + r * 0.1, y: c.y - r * 0.5))
            context.stroke(g, with: .color(.white.opacity(0.55)),
                           style: StrokeStyle(lineWidth: max(0.5, r * 0.22), lineCap: .round))
        }

        switch kind {
        case .none:
            break

        case .glasses:
            var frames = Path()
            frames.addPath(circle(left, lensR))
            frames.addPath(circle(right, lensR))
            context.fill(frames, with: .color(.white.opacity(0.18)))
            context.stroke(frames, with: .color(tint), lineWidth: line)
            var bridge = Path()
            bridge.move(to: CGPoint(x: left.x + lensR, y: anchor.y - lensR * 0.15))
            bridge.addLine(to: CGPoint(x: right.x - lensR, y: anchor.y - lensR * 0.15))
            context.stroke(bridge, with: .color(tint), lineWidth: line)
            glint(left, lensR)

        case .sunglasses:
            let w = lensR * 2.1, h = lensR * 1.7
            var lenses = Path()
            lenses.addRoundedRect(in: CGRect(x: left.x - w / 2, y: anchor.y - h / 2, width: w, height: h),
                                   cornerSize: CGSize(width: h * 0.42, height: h * 0.42))
            lenses.addRoundedRect(in: CGRect(x: right.x - w / 2, y: anchor.y - h / 2, width: w, height: h),
                                   cornerSize: CGSize(width: h * 0.42, height: h * 0.42))
            context.fill(lenses, with: .color(dark))
            var bridge = Path()
            bridge.move(to: CGPoint(x: left.x + w / 2, y: anchor.y - h * 0.2))
            bridge.addLine(to: CGPoint(x: right.x - w / 2, y: anchor.y - h * 0.2))
            context.stroke(bridge, with: .color(tint), lineWidth: line * 1.6)
            glint(left, lensR * 0.9)
            glint(right, lensR * 0.9)

        case .visor:
            // One wraparound band across both eyes.
            let w = (spacing * 2) + lensR * 2.4
            let h = lensR * 1.6
            let rect = CGRect(x: anchor.x - w / 2, y: anchor.y - h / 2, width: w, height: h)
            var band = Path()
            band.addRoundedRect(in: rect, cornerSize: CGSize(width: h * 0.5, height: h * 0.5))
            context.fill(band, with: .color(dark))
            context.stroke(band, with: .color(tint), lineWidth: line * 1.4)
            var sheen = Path()
            sheen.move(to: CGPoint(x: rect.minX + w * 0.12, y: rect.maxY - h * 0.22))
            sheen.addLine(to: CGPoint(x: rect.minX + w * 0.42, y: rect.minY + h * 0.24))
            context.stroke(sheen, with: .color(tint.opacity(0.75)),
                           style: StrokeStyle(lineWidth: max(0.5, h * 0.16), lineCap: .round))

        case .monocle:
            let r = lensR * 1.15
            let lens = circle(right, r)
            context.fill(lens, with: .color(.white.opacity(0.2)))
            context.stroke(lens, with: .color(tint), lineWidth: line * 1.5)
            var chain = Path()
            chain.move(to: CGPoint(x: right.x, y: right.y + r))
            chain.addQuadCurve(to: CGPoint(x: right.x + r * 0.5, y: right.y + r * 2.4),
                                control: CGPoint(x: right.x + r * 0.9, y: right.y + r * 1.5))
            context.stroke(chain, with: .color(tint.opacity(0.85)),
                           style: StrokeStyle(lineWidth: max(0.4, line * 0.8), lineCap: .round))
            glint(right, r)

        case .eyePatch:
            let w = lensR * 2.0, h = lensR * 1.9
            var patch = Path()
            patch.addRoundedRect(in: CGRect(x: left.x - w / 2, y: anchor.y - h / 2, width: w, height: h),
                                  cornerSize: CGSize(width: w * 0.38, height: h * 0.38))
            context.fill(patch, with: .color(dark))
            var strap = Path()
            strap.move(to: CGPoint(x: left.x - w * 0.85, y: anchor.y - h * 0.62))
            strap.addLine(to: CGPoint(x: right.x + w * 0.5, y: anchor.y - h * 0.18))
            context.stroke(strap, with: .color(tint.opacity(0.9)),
                           style: StrokeStyle(lineWidth: max(0.4, line * 0.9), lineCap: .round))
        }
    }

    /// Draws `DotStyle.Accessory` — a second worn item beyond the hat (§ new
    /// — "more cloths") — as a simple vector shape rather than an SF Symbol,
    /// anchored at roughly chest height in the body's own local frame so it
    /// moves and rotates with the dot exactly like the hat does. `.none`
    /// draws nothing.
    private static func drawAccessory(_ context: GraphicsContext, front: CGFloat, back: CGFloat,
                                       top: CGFloat, bottom: CGFloat, kind: DotStyle.Accessory,
                                       tint: Color, bodyPath: Path) {
        guard kind != .none else { return }
        let chest = CGPoint(x: front * 0.05, y: top * 0.48)

        switch kind {
        case .none:
            break

        case .bowtie:
            // Two mirrored triangles meeting at a small center knot.
            let w = top * 0.5
            let h = top * 0.28
            var path = Path()
            path.move(to: chest)
            path.addLine(to: CGPoint(x: chest.x - w / 2, y: chest.y - h / 2))
            path.addLine(to: CGPoint(x: chest.x - w / 2, y: chest.y + h / 2))
            path.closeSubpath()
            path.move(to: chest)
            path.addLine(to: CGPoint(x: chest.x + w / 2, y: chest.y - h / 2))
            path.addLine(to: CGPoint(x: chest.x + w / 2, y: chest.y + h / 2))
            path.closeSubpath()
            context.fill(path, with: .color(tint))
            let knotR = h * 0.3
            context.fill(
                Path(ellipseIn: CGRect(x: chest.x - knotR, y: chest.y - knotR, width: knotR * 2, height: knotR * 2)),
                with: .color(tint.mix(with: .black, amount: 0.3))
            )

        case .scarf:
            // A thick band across the lower body, clipped to the silhouette
            // (§ new — "remove their hands"): this used to be a stroked arc
            // with round caps, whose two ends poked out either side of the
            // dot and read as little arms reaching out.
            var scarfContext = context
            scarfContext.clip(to: bodyPath)
            var path = Path()
            let r = top * 0.6
            path.addArc(center: CGPoint(x: 0, y: top * 0.1), radius: r,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            scarfContext.stroke(path, with: .color(tint),
                                style: StrokeStyle(lineWidth: top * 0.24, lineCap: .butt))

        case .collar:
            // Same fix as `.scarf` — clipped, butt caps, no protruding ends.
            var collarContext = context
            collarContext.clip(to: bodyPath)
            var path = Path()
            let r = top * 0.48
            path.addArc(center: CGPoint(x: 0, y: -top * 0.02), radius: r,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            collarContext.stroke(path, with: .color(tint),
                                 style: StrokeStyle(lineWidth: top * 0.11, lineCap: .butt))

        case .tie:
            // A small knot with a tapered tie hanging below it, all well
            // inside the silhouette.
            let knotW = top * 0.16
            let knotH = top * 0.13
            var knot = Path()
            knot.addRoundedRect(in: CGRect(x: chest.x - knotW / 2, y: chest.y - knotH,
                                            width: knotW, height: knotH),
                                 cornerSize: CGSize(width: knotW * 0.3, height: knotW * 0.3))
            context.fill(knot, with: .color(tint.mix(with: .black, amount: 0.25)))
            var blade = Path()
            blade.move(to: CGPoint(x: chest.x - knotW * 0.42, y: chest.y))
            blade.addLine(to: CGPoint(x: chest.x + knotW * 0.42, y: chest.y))
            blade.addLine(to: CGPoint(x: chest.x + knotW * 0.30, y: chest.y + top * 0.38))
            blade.addLine(to: CGPoint(x: chest.x, y: chest.y + top * 0.48))
            blade.addLine(to: CGPoint(x: chest.x - knotW * 0.30, y: chest.y + top * 0.38))
            blade.closeSubpath()
            context.fill(blade, with: .color(tint))

        case .chain:
            // A row of small linked beads following the neckline curve.
            let r = top * 0.42
            let beadR = max(0.5, top * 0.055)
            for i in 0...8 {
                let t = Double(i) / 8.0
                let angle = Double.pi * (0.12 + t * 0.76)
                let x = CGFloat(cos(angle)) * r * -1
                let y = CGFloat(sin(angle)) * r * 0.62 + top * 0.06
                context.fill(
                    Path(ellipseIn: CGRect(x: x - beadR, y: y - beadR, width: beadR * 2, height: beadR * 2)),
                    with: .color(tint)
                )
            }

        case .cape:
            // A soft curved shape draped from the back, trailing behind the
            // body's tail — reads as fabric flowing rather than a rigid slab.
            let backX = -back * 0.75
            var path = Path()
            path.move(to: CGPoint(x: backX * 0.6, y: -top * 0.5))
            path.addQuadCurve(to: CGPoint(x: backX * 1.5, y: bottom * 0.6),
                               control: CGPoint(x: backX * 1.7, y: -top * 0.1))
            path.addQuadCurve(to: CGPoint(x: backX * 0.7, y: bottom * 0.7),
                               control: CGPoint(x: backX * 1.1, y: bottom * 1.0))
            path.addQuadCurve(to: CGPoint(x: backX * 0.6, y: -top * 0.5),
                               control: CGPoint(x: backX * 0.75, y: 0))
            path.closeSubpath()
            var capeContext = context
            capeContext.opacity = 0.88
            capeContext.fill(path, with: .color(tint))

        case .medal:
            // A short ribbon with a small round medallion at chest height.
            let ribbonWidth = top * 0.12
            let ribbonHeight = top * 0.3
            let ribbonRect = CGRect(x: chest.x - ribbonWidth / 2, y: chest.y - ribbonHeight,
                                     width: ribbonWidth, height: ribbonHeight)
            context.fill(Path(ribbonRect), with: .color(tint.mix(with: .black, amount: 0.2)))
            let r = top * 0.17
            let medalRect = CGRect(x: chest.x - r, y: chest.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: medalRect), with: .color(tint))
            context.stroke(Path(ellipseIn: medalRect), with: .color(.white.opacity(0.65)), lineWidth: max(0.6, r * 0.12))
        }
    }

    /// See the call site in `drawPlayer` above for the full rationale. Sized
    /// off `top` (the body's own current top radius) so it scales with the
    /// dot and stays anchored to the same point regardless of squash/stretch.
    /// `hatSymbol` comes from `DotStyle.visual` — `nil` wears nothing.
    private static func drawHat(_ context: GraphicsContext, top: CGFloat, hatSymbol: String?, tint: Color) {
        guard let symbolName = hatSymbol else { return }
        let size = top * 0.95
        let anchor = CGPoint(x: 0, y: -top * 1.12)
        // `Image` alone has no `.font`/`.foregroundColor` of its own (those
        // are plain `View` modifiers that would return `some View`, which
        // `GraphicsContext.draw` can't take) — wrapping it in `Text` first,
        // the same trick already used for the emoji icons elsewhere in this
        // file, is what lets an SF Symbol be sized and tinted before landing
        // in a Canvas.
        let icon = Text(Image(systemName: symbolName))
            .font(.system(size: size, weight: .bold))
            .foregroundColor(tint)
        // No drop shadow behind the glyph (§ new — "remove the shadow from
        // the hats"): the hat is already a contrasting colour against the
        // body, so the shadow only muddied it at small sizes.
        context.draw(icon, at: anchor)
    }

    /// Builds a closed, smooth "liquid blob" outline: round on the `front`/
    /// `top`/`bottom` side (normal circle roundness), tapering toward more of
    /// a point on the `back` side (a smaller `tailKappa`) — the shared shape
    /// behind both the player's squash-and-stretch body and the absorb
    /// effect's traveling droplet. All radii are measured from the local
    /// origin; `front` points toward +x, `back` toward -x.
    private static func blobOutline(front: CGFloat, back: CGFloat, top: CGFloat, bottom: CGFloat,
                                     tailKappa: CGFloat, noseKappa: CGFloat = 0.5523) -> Path {
        let pFront = CGPoint(x: front, y: 0)
        let pTop = CGPoint(x: 0, y: -top)
        let pBack = CGPoint(x: -back, y: 0)
        let pBottom = CGPoint(x: 0, y: bottom)

        var path = Path()
        path.move(to: pFront)

        let (c1a, c2a) = quarterCurveControls(pFront, pTop, kappa: noseKappa)
        path.addCurve(to: pTop, control1: c1a, control2: c2a)

        let (c1b, c2b) = quarterCurveControls(pTop, pBack, kappa: tailKappa)
        path.addCurve(to: pBack, control1: c1b, control2: c2b)

        let (c1c, c2c) = quarterCurveControls(pBack, pBottom, kappa: tailKappa)
        path.addCurve(to: pBottom, control1: c1c, control2: c2c)

        let (c1d, c2d) = quarterCurveControls(pBottom, pFront, kappa: noseKappa)
        path.addCurve(to: pFront, control1: c1d, control2: c2d)

        path.closeSubpath()
        return path
    }

    /// Bezier control points for a quarter-ellipse arc between two points
    /// that each sit on one axis — exactly what every corner of `blobOutline`
    /// is. The standard "kappa" circle/ellipse approximation, generalized to
    /// whichever of the two points happens to be on which axis.
    private static func quarterCurveControls(_ p1: CGPoint, _ p2: CGPoint, kappa: CGFloat) -> (CGPoint, CGPoint) {
        if p1.y == 0 {
            // p1 lies on the x-axis, p2 on the y-axis.
            return (CGPoint(x: p1.x, y: p2.y * kappa), CGPoint(x: p1.x * kappa, y: p2.y))
        } else {
            // p1 lies on the y-axis, p2 on the x-axis.
            return (CGPoint(x: p2.x * kappa, y: p1.y), CGPoint(x: p2.x, y: p1.y * kappa))
        }
    }

    /// A small stretched "liquid" droplet — round leading edge, tapering
    /// tail — used for the absorb effect's travel arc. `elongation` 0 = a
    /// plain circle (used right as it rounds out into the merge), 1 = a long
    /// drawn-out tail (used right after being eaten, when it's "moving fastest").
    static func liquidDropletPath(radius: CGFloat, elongation: CGFloat) -> Path {
        let e = min(1, max(0, elongation))
        let front = radius * (1 + e * 0.25)
        let back = radius * (1 + e * 2.1)
        let side = radius * (1 - e * 0.55)
        let tailKappa: CGFloat = 0.5523 * (1 - e * 0.6)
        return blobOutline(front: front, back: back, top: side, bottom: side, tailKappa: tailKappa)
    }

    /// - anchor: the eyes' one fixed spot, already in whatever local frame
    ///   `context` draws in (the player's rotated/stretched body frame, or
    ///   plain world space for the main menu's non-moving preview dot).
    /// - scale: a representative body radius at that spot, driving every
    ///   proportion below — so the eyes grow/shrink with the body's current
    ///   shape instead of a single fixed radius.
    private static func drawEyes(_ context: GraphicsContext, anchor: CGPoint, scale: CGFloat,
                                  lookDirection: CGVector, time: Double, style: EyeStyle) {
        // Pulled in closer to center (less gap between the two eyes) so each
        // one sits further from the body's own left/right edge, regardless
        // of the dot's overall scale since this stays a plain proportion of it.
        let eyeSpacing = scale * 0.22
        // Taller than wide — a narrow vertical oval reads softer and more
        // expressive than a plain round dot for an eye. Widened a touch
        // again (§ user feedback: "fix the eyes and look of the dot") so
        // they read as clearer, friendlier eyes rather than thin slits.
        let eyeRadiusX = scale * 0.09
        let eyeRadiusY = scale * 0.25
        let pupilRadius = eyeRadiusX * 0.6
        let openAmount = blinkOpenAmount(time)
        let sides: [CGFloat] = [-1, 1]

        // With no pupil to slide around in the `.whiteOnly` style, "looking"
        // a direction instead reads through the eye itself: glancing up/down
        // opens it taller/shorter (as before), and glancing left/right now
        // also slides the whole eye pair sideways together — like a BB-8-ish
        // pair of eyes shifting as one, rather than an independent pupil
        // moving inside a fixed white oval (that's still what `.withPupil`
        // does, unaffected by this).
        let lookHeightScale = max(0.55, min(1.45, 1 - CGFloat(lookDirection.dy) * 0.4))
        let maxHorizontalShift = eyeRadiusX * 0.55
        let horizontalShift = style == .whiteOnly ? CGFloat(lookDirection.dx) * maxHorizontalShift : 0

        for side in sides {
            let eyeCenter = CGPoint(x: anchor.x + side * eyeSpacing + horizontalShift, y: anchor.y)
            let baseEyeHeight = eyeRadiusY * lookHeightScale
            let scleraHalfHeight = max(baseEyeHeight * 0.12, baseEyeHeight * CGFloat(openAmount))
            // A softly rounded rect rather than a plain lens/oval shape —
            // dialed back toward fuller, softer corners again per user
            // feedback ("make the eyes more rounded") after an earlier pass
            // had flattened them more than they wanted.
            let scleraRect = CGRect(x: eyeCenter.x - eyeRadiusX, y: eyeCenter.y - scleraHalfHeight,
                                     width: eyeRadiusX * 2, height: scleraHalfHeight * 2)
            let scleraCornerRadius = eyeRadiusX * 0.8
            let scleraPath = Path(roundedRect: scleraRect, cornerRadius: scleraCornerRadius)

            // No shadow behind the eye (§ new — "remove the shadows from the
            // dots"): the sclera sits flat on the body like everything else.

            // A subtle top-lit gradient instead of a flat white fill — the
            // same "lit from above" language as the body's own gradient —
            // plus a thin, soft outline so the eye keeps its own shape
            // clearly defined even against a light-colored dot.
            context.fill(
                scleraPath,
                with: .linearGradient(Gradient(colors: [.white, Color(white: 0.92)]),
                                       startPoint: CGPoint(x: eyeCenter.x, y: scleraRect.minY),
                                       endPoint: CGPoint(x: eyeCenter.x, y: scleraRect.maxY))
            )
            context.stroke(scleraPath, with: .color(.black.opacity(0.12)), lineWidth: max(0.6, eyeRadiusX * 0.12))

            guard style == .withPupil, openAmount > 0.3 else { continue }
            let maxOffsetX = eyeRadiusX - pupilRadius
            let maxOffsetY = baseEyeHeight - pupilRadius
            let pupilCenter = CGPoint(
                x: eyeCenter.x + lookDirection.dx * maxOffsetX * 0.6,
                y: eyeCenter.y + lookDirection.dy * maxOffsetY * 0.6 * CGFloat(openAmount)
            )
            let pupilVisibleRadius = pupilRadius * CGFloat(openAmount)
            // A near-black (not pure flat black) radial fill gives the pupil
            // a touch of its own depth, and a tiny bright catch-light on top
            // — offset toward the same top-right light direction as every
            // other highlight in the game — is what actually makes the eye
            // read as glossy and alive instead of a dead painted dot.
            context.fill(
                Path(ellipseIn: CGRect(x: pupilCenter.x - pupilVisibleRadius, y: pupilCenter.y - pupilVisibleRadius,
                                        width: pupilVisibleRadius * 2, height: pupilVisibleRadius * 2)),
                with: .radialGradient(Gradient(colors: [Color(white: 0.22), .black]),
                                       center: CGPoint(x: pupilCenter.x - pupilVisibleRadius * 0.3, y: pupilCenter.y - pupilVisibleRadius * 0.3),
                                       startRadius: 0, endRadius: pupilVisibleRadius * 1.3)
            )
            let catchLightRadius = pupilVisibleRadius * 0.38
            let catchLightCenter = CGPoint(x: pupilCenter.x - pupilVisibleRadius * 0.32, y: pupilCenter.y - pupilVisibleRadius * 0.35)
            context.fill(
                Path(ellipseIn: CGRect(x: catchLightCenter.x - catchLightRadius, y: catchLightCenter.y - catchLightRadius,
                                        width: catchLightRadius * 2, height: catchLightRadius * 2)),
                with: .color(.white.opacity(0.9))
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

    /// A colour deliberately *unlike* the body's, for worn items (§ new —
    /// hats and clothing used to be tinted with the body's own light/dark
    /// shades, so a hat read as a pale patch of the same dot rather than as
    /// something the dot is wearing). Rotates the hue away from the body's
    /// and forces a high brightness, so the item stays vivid and legible on
    /// any dot — including the near-grey styles, which get enough saturation
    /// here to show a real colour.
    func wornAccent(hueShift: Double) -> Color {
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var shifted = (Double(h) + hueShift).truncatingRemainder(dividingBy: 1.0)
        if shifted < 0 { shifted += 1 }
        return Color(hue: shifted,
                      saturation: min(0.88, max(0.62, Double(s))),
                      brightness: max(0.94, Double(b)),
                      opacity: Double(a))
        #else
        return self
        #endif
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
