import SwiftUI

/// A deep blue-to-violet sky with stars streaking past, used behind the
/// falling-dot intro so arriving in a universe starts in motion rather than
/// on a flat black screen.
struct WarpBackdrop: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                // Vertical streaks: the dot is falling, so the sky rushes up.
                for i in 0..<46 {
                    let seed = Double(i) * 12.9898
                    let x = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1) * size.width
                    let speed = 220 + abs(sin(seed * 1.7)) * 520
                    let length = 14 + abs(sin(seed * 2.3)) * 60
                    let y = size.height + length - CGFloat((t * speed + abs(sin(seed * 3.1)) * 2000).truncatingRemainder(dividingBy: Double(size.height) + Double(length) * 2))
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x, y: y + length))
                    ctx.stroke(p, with: .color(.white.opacity(0.18 + abs(sin(seed * 5.1)) * 0.4)),
                               style: StrokeStyle(lineWidth: 1 + abs(sin(seed * 4.3)) * 1.4, lineCap: .round))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Plays over the universe as the player arrives: the screen is covered by
/// the universe's colour with rings rushing outward, the name settles in,
/// then a round window opens from the dot and reveals the world.
struct UniverseEntryOverlay: View {
    let title: String
    let caption: String
    let color: Color
    let accent: Color
    var onFinished: () -> Void = {}

    static let holdTime: Double = 0.8
    static let openTime: Double = 0.85

    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            GeometryReader { geo in
                Canvas { ctx, size in draw(ctx, size: size, t: t) }
                    .overlay {
                        VStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text(caption)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .scaleEffect(titleScale(t))
                        .opacity(titleOpacity(t))
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.32)
                    }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { start = Date() }
        .task {
            try? await Task.sleep(nanoseconds: UInt64((Self.holdTime + Self.openTime + 0.1) * 1_000_000_000))
            finished = true
            onFinished()
        }
        .opacity(finished ? 0 : 1)
    }

    private func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    private func titleScale(_ t: Double) -> CGFloat {
        let appear = min(1, max(0, t / 0.45))
        let leave = min(1, max(0, (t - Self.holdTime * 0.75) / 0.5))
        return CGFloat(max(0.01, easeOutBack(appear)) * (1 + 0.25 * leave))
    }

    private func titleOpacity(_ t: Double) -> Double {
        let appear = min(1, t / 0.25)
        let leave = min(1, max(0, (t - Self.holdTime * 0.75) / 0.45))
        return appear * (1 - leave)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let diagonal = hypot(size.width, size.height)
        // Window radius: closed during the hold, then opens fast and eases out.
        let openT = min(1, max(0, (t - Self.holdTime) / Self.openTime))
        let eased = 1 - pow(1 - openT, 3)
        let radius = diagonal * 0.56 * eased

        var cover = Path(CGRect(origin: .zero, size: size))
        if radius > 0.5 {
            cover.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        // Black, with a soft glow of the universe's colour in the middle.
        ctx.fill(cover, with: .color(.black), style: FillStyle(eoFill: true))
        let glow = diagonal * 0.5 * (1 - openT)
        if glow > 1 {
            var holed = ctx
            holed.clip(to: cover, style: FillStyle(eoFill: true))
            holed.fill(Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                       with: .radialGradient(Gradient(colors: [accent.opacity(0.35), .clear]), center: center, startRadius: 0, endRadius: glow))
        }
    }
}
