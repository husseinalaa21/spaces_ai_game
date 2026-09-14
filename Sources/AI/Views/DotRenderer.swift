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
                            dotStyle: DotStyle = .classic, showGroundShadow: Bool = true) {
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
        // Kept for the shadow below, which only wants a coarse sense of how
        // deformed the body currently is, not the per-side detail above.
        let idleWobble = (frontWobble + backWobble + topWobble + bottomWobble) / 4

        // Raised briefly right after eating something (see `WhiteSpaceView`'s
        // arrival flash) to richen the glow/highlight below — computed early
        // since the new ambient glow (drawn before the body itself) needs it too.
        let pulse = max(0, min(1, eatPulse))

        // A soft, blurred ground shadow — flattened, offset a little below
        // center, and deliberately NOT rotated/stretched with the body — so
        // the dot reads as sitting on the grid instead of being a flat
        // sticker painted onto it. Drawn first, underneath everything.
        // Skipped entirely inside White Space itself (§ user feedback: "the
        // border shadow around the dots" in the universe should go) — still
        // used for the main menu's preview dot, which isn't sitting on any
        // grid to ground it against.
        if showGroundShadow {
            var shadowContext = context
            shadowContext.opacity = 0.15
            shadowContext.addFilter(.blur(radius: radius * 0.18))
            let shadowWidth = radius * (1.5 + shapeStretch * 0.4 + idleWobble * 0.5)
            let shadowHeight = radius * 0.55
            let shadowCenter = CGPoint(x: center.x, y: center.y + radius * 0.62)
            shadowContext.fill(
                Path(ellipseIn: CGRect(x: shadowCenter.x - shadowWidth / 2, y: shadowCenter.y - shadowHeight / 2,
                                        width: shadowWidth, height: shadowHeight)),
                with: .color(.black)
            )
        }

        // The cosmetic dot style (§28/§29, now a much bigger catalog — see
        // `DotStyle.visual`) tints the base transformation color and
        // richens the shine a little — it never replaces the color itself,
        // so the dot still tells you what you're becoming. Rainbow's accent
        // cycles hue over time instead of staying fixed; everything else
        // uses its own fixed accent. Computed before the body itself so the
        // ambient glow just below (drawn in world space, behind the body)
        // can already use it.
        let visual = dotStyle.visual
        let effectiveAccent: Color
        if visual.hasRainbow {
            let hue = (time / 5.0).truncatingRemainder(dividingBy: 1.0)
            effectiveAccent = Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.85, brightness: 1.0)
        } else {
            effectiveAccent = visual.accentColor
        }
        let styledColor = visual.mixAmount > 0 ? color.mix(with: effectiveAccent, amount: visual.mixAmount) : color
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

        // A faint, darker fresnel rim on the opposite (shadow) side — the
        // same "far-edge falloff" cue a professional 3D render uses for
        // contrast, so the body reads as genuinely lit from one direction
        // rather than evenly lit all the way around.
        let shadowRim = bodyPath.trimmedPath(from: 0.55, to: 0.72)
        var shadowRimContext = bodyContext
        shadowRimContext.opacity = 0.32
        shadowRimContext.addFilter(.blur(radius: max(0.4, radius * 0.03)))
        shadowRimContext.stroke(shadowRim, with: .color(darkShade.mix(with: .black, amount: 0.4)),
                                 style: StrokeStyle(lineWidth: max(1, radius * 0.06), lineCap: .round))

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
        drawEyes(bodyContext, anchor: eyeAnchor, scale: eyeScale, lookDirection: localLook, time: time, style: eyeStyle)

        // A second worn item below the hat (§ new — "more cloths": a bowtie,
        // scarf, collar, cape, or medal per style — see `DotStyle.Accessory`)
        // — a simple drawn vector shape rather than another SF Symbol, so it
        // clearly reads as something worn low on the body rather than a
        // second badge stacked on the head. Tinted with `darkShade` (the
        // body's own richer, darker gradient tone) so it visibly contrasts
        // with the hat's lighter `lightShade` tint just below.
        drawAccessory(bodyContext, front: front, back: back, top: top, bottom: bottom,
                      kind: visual.accessory, tint: darkShade)

        // A small worn accessory for premium Dot Styles (§ new — user asked
        // for something like "wearing a hat" so a premium pick reads at a
        // glance, not just through a tinted body): drawn last, perched right
        // on top of the head, in the same rotated/stretched local frame as
        // everything else above so it rides along with the body's motion.
        // Real SF Symbols glyphs (§ user feedback: hand-drawn shapes didn't
        // read right — "look up in the libraries", i.e. the system icon set
        // already used elsewhere in this app, like the Store's pack icons)
        // rather than custom vector paths, tinted with the body's own
        // `lightShade` so it still visibly belongs to the same dot. `.classic`
        // gets nothing.
        drawHat(bodyContext, top: top, hatSymbol: visual.hatSymbol, tint: lightShade)
    }

    /// Draws `DotStyle.Accessory` — a second worn item beyond the hat (§ new
    /// — "more cloths") — as a simple vector shape rather than an SF Symbol,
    /// anchored at roughly chest height in the body's own local frame so it
    /// moves and rotates with the dot exactly like the hat does. `.none`
    /// draws nothing.
    private static func drawAccessory(_ context: GraphicsContext, front: CGFloat, back: CGFloat,
                                       top: CGFloat, bottom: CGFloat, kind: DotStyle.Accessory, tint: Color) {
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
            // A thick, soft loop wrapping the lower-front of the body.
            var path = Path()
            let r = top * 0.6
            path.addArc(center: CGPoint(x: 0, y: top * 0.1), radius: r,
                        startAngle: .degrees(15), endAngle: .degrees(165), clockwise: false)
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: top * 0.22, lineCap: .round))

        case .collar:
            // A thinner ring right at the neckline, just below the eyes.
            var path = Path()
            let r = top * 0.48
            path.addArc(center: CGPoint(x: 0, y: -top * 0.02), radius: r,
                        startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: top * 0.1, lineCap: .round))

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
        let size = top * 0.9
        let anchor = CGPoint(x: 0, y: -top * 1.05)
        // `Image` alone has no `.font`/`.foregroundColor` of its own (those
        // are plain `View` modifiers that would return `some View`, which
        // `GraphicsContext.draw` can't take) — wrapping it in `Text` first,
        // the same trick already used for the emoji icons elsewhere in this
        // file, is what lets an SF Symbol be sized and tinted before landing
        // in a Canvas.
        let icon = Text(Image(systemName: symbolName))
            .font(.system(size: size, weight: .bold))
            .foregroundColor(tint)
        // A soft dark shadow directly behind the glyph reads as depth/lift
        // off the head — the same "grounding" role the body's own ground
        // shadow plays, just scaled down for a small worn accessory.
        var shadowContext = context
        shadowContext.opacity = 0.22
        shadowContext.addFilter(.blur(radius: size * 0.12))
        shadowContext.draw(Text(Image(systemName: symbolName)).font(.system(size: size, weight: .bold)).foregroundColor(.black),
                            at: CGPoint(x: anchor.x, y: anchor.y + size * 0.06))
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

            // A soft shadow seats the eye into the body's surface instead of
            // it reading as a flat sticker floating on top (§ user feedback:
            // "fix the eyes and look of the dot").
            var eyeShadowContext = context
            eyeShadowContext.opacity = 0.16
            eyeShadowContext.addFilter(.blur(radius: eyeRadiusX * 0.5))
            eyeShadowContext.fill(scleraPath, with: .color(.black))

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
