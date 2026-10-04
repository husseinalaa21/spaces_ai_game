import SwiftUI

// The Spacechat app's dots, ported as they are: a shaped body with a gradient and an outline, a glossy highlight, white eyes that
// look around and blink, and one dot at a time that shakes. Spaces uses them for every agent.

@MainActor
final class SpacechatDotShaker: ObservableObject {
    static let shared = SpacechatDotShaker()
    @Published private(set) var activeId: String?
    private var counts: [String: Int] = [:]
    private var timer: Timer?

    func register(_ id: String) {
        counts[id, default: 0] += 1
        if timer == nil {
            pick()
            timer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pick() }
            }
        }
    }

    func unregister(_ id: String) {
        guard let count = counts[id] else { return }
        if count <= 1 { counts.removeValue(forKey: id) } else { counts[id] = count - 1 }
        if counts.isEmpty {
            timer?.invalidate()
            timer = nil
            activeId = nil
        } else if activeId == id {
            pick()
        }
    }

    private func pick() { activeId = counts.keys.randomElement() }
}

enum SpacechatDotGeometry {
    static let shapeNames = ["circle", "squircle", "star", "drop", "hexagon", "heart", "cloud", "triangle", "octagon", "star6", "blob", "diamond", "gear", "pentagon", "plus", "burst", "flower", "star4"]
    static let eyes: [String: (y: Double, scale: Double)] = [
        "circle": (50, 1), "star": (54, 0.7), "heart": (44, 0.9), "hexagon": (50, 1), "flower": (50, 0.9), "diamond": (50, 0.8),
        "star4": (50, 0.62), "star6": (50, 0.82), "burst": (50, 0.95), "gear": (50, 0.95), "triangle": (64, 0.7), "pentagon": (52, 1),
        "octagon": (50, 1), "squircle": (50, 1), "drop": (60, 0.88), "plus": (50, 0.95), "cloud": (50, 0.95), "blob": (50, 1),
    ]
    static let brandHues: [String: Double] = ["chatgpt": 160, "gemini": 255, "claude": 22, "grok": 215, "spaceai": 200]

    /// The same string hash the web client uses, so a dot looks the same on both.
    static func hash(_ text: String) -> UInt32 {
        var value: UInt32 = 7
        for scalar in text.unicodeScalars { value = value &* 31 &+ UInt32(scalar.value & 0xFFFF) }
        return value
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private static func polar(_ count: Int, inner: Double, outer: Double = 46, rotation: Double = -Double.pi / 2) -> [CGPoint] {
        (0..<(count * 2)).map { index in
            let angle = rotation + Double(index) * Double.pi / Double(count)
            let radius = index % 2 == 0 ? outer : inner
            return CGPoint(x: 50 + cos(angle) * radius, y: 50 + sin(angle) * radius)
        }
    }

    private static func flower(_ petals: Int, base: Double, bump: Double) -> [CGPoint] {
        (0...120).map { index in
            let angle = Double(index) / 120 * Double.pi * 2 - Double.pi / 2
            let radius = base + bump * cos(Double(petals) * (angle + Double.pi / 2))
            return CGPoint(x: 50 + cos(angle) * radius, y: 50 + sin(angle) * radius)
        }
    }

    private static func regular(_ count: Int, radius: Double = 46, rotation: Double = -Double.pi / 2) -> [CGPoint] {
        (0..<count).map { index in
            let angle = rotation + Double(index) * 2 * Double.pi / Double(count)
            return CGPoint(x: 50 + cos(angle) * radius, y: 50 + sin(angle) * radius)
        }
    }

    private static func curves(_ start: CGPoint, _ segments: [(CGPoint, CGPoint, CGPoint)]) -> Path {
        var path = Path()
        path.move(to: start)
        segments.forEach { path.addCurve(to: $0.2, control1: $0.0, control2: $0.1) }
        path.closeSubpath()
        return path
    }

    static func path(_ shape: String) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        switch shape {
        case "bolt": return polygon([p(58, 4), p(20, 56), p(46, 56), p(38, 96), p(80, 40), p(54, 40)])
        case "star": return polygon(polar(5, inner: 22))
        case "star4": return polygon(polar(4, inner: 24))
        case "star6": return polygon(polar(6, inner: 30))
        case "burst": return polygon(polar(10, inner: 36))
        case "gear": return polygon(polar(8, inner: 38, outer: 47))
        case "hexagon": return polygon([p(50, 4), p(90, 27), p(90, 73), p(50, 96), p(10, 73), p(10, 27)])
        case "triangle": return polygon([p(50, 6), p(95, 88), p(5, 88)])
        case "diamond": return polygon([p(50, 4), p(86, 50), p(50, 96), p(14, 50)])
        case "pentagon": return polygon(regular(5))
        case "octagon": return polygon(regular(8, radius: 47, rotation: Double.pi / 8))
        case "plus": return polygon([p(36, 5), p(64, 5), p(64, 36), p(95, 36), p(95, 64), p(64, 64), p(64, 95), p(36, 95), p(36, 64), p(5, 64), p(5, 36), p(36, 36)])
        case "cloud": return polygon(flower(6, base: 38, bump: 8))
        case "flower": return polygon(flower(5, base: 34, bump: 12))
        case "squircle": return Path(roundedRect: CGRect(x: 5, y: 5, width: 90, height: 90), cornerRadius: 21)
        case "blob":
            return curves(p(50, 6), [(p(72, 4), p(94, 22), p(93, 48)), (p(92, 74), p(74, 95), p(48, 94)), (p(24, 93), p(6, 74), p(7, 50)), (p(8, 26), p(28, 8), p(50, 6))])
        case "drop":
            return curves(p(50, 4), [(p(50, 4), p(16, 42), p(16, 64)), (p(16, 82), p(31, 95), p(50, 95)), (p(69, 95), p(84, 82), p(84, 64)), (p(84, 42), p(50, 4), p(50, 4))])
        case "heart":
            return curves(p(50, 90), [(p(14, 62), p(6, 40), p(12, 26)), (p(20, 8), p(42, 10), p(50, 28)), (p(58, 10), p(80, 8), p(88, 26)), (p(94, 40), p(86, 62), p(50, 90))])
        default: return Path(ellipseIn: CGRect(x: 6, y: 6, width: 88, height: 88))
        }
    }

    static func color(h: Double, s: Double, l: Double) -> Color {
        let sat = s / 100
        let light = l / 100
        let v = light + sat * min(light, 1 - light)
        let hsbS = v == 0 ? 0 : 2 * (1 - light / v)
        return Color(hue: (h.truncatingRemainder(dividingBy: 360)) / 360, saturation: hsbS, brightness: v)
    }
}

struct SpacechatDotFace: View {
    let key: String
    var size: CGFloat = 40
    var animated: Bool = true
    /// Use this colour (degrees) instead of the one worked out from the key, e.g. an agent's own colour.
    var hue: Double? = nil
    /// Use this shape (one of `SpacechatDotGeometry.shapeNames`) instead of the one worked out from the key.
    var shape: String? = nil

    @ObservedObject private var shaker = SpacechatDotShaker.shared
    @State private var identity = UUID().uuidString

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation) { timeline in
                    dot(time: timeline.date.timeIntervalSinceReferenceDate, shaking: shaker.activeId == identity)
                }
            } else {
                dot(time: 0, shaking: false)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { if animated { shaker.register(identity) } }
        .onDisappear { if animated { shaker.unregister(identity) } }
    }

    private func dot(time: Double, shaking: Bool) -> some View {
        let h = SpacechatDotGeometry.hash(key)
        let shape = self.shape ?? SpacechatDotGeometry.shapeNames[Int(h) % SpacechatDotGeometry.shapeNames.count]
        let hue = self.hue ?? SpacechatDotGeometry.brandHues[key] ?? Double((h >> 3) % 360)
        let eye = SpacechatDotGeometry.eyes[shape] ?? (50, 1)
        let amplitude = 2 + Double(h % 4) * 0.8
        let lookPeriod = 7 + Double(h % 5) * 1.3
        let lookShift = -Double(h % 7) * 1.1
        let blinkPeriod = 3.4 + Double(h % 6) * 0.6
        let blinkShift = -Double(h % 9) * 0.5
        let path = SpacechatDotGeometry.path(shape)
        let stroke = SpacechatDotGeometry.color(h: hue, s: 78, l: 46)
        let light = SpacechatDotGeometry.color(h: hue, s: 88, l: 70)
        let dark = SpacechatDotGeometry.color(h: hue, s: 80, l: 52)

        return Canvas { context, canvasSize in
            let unit = canvasSize.width / 100
            context.scaleBy(x: unit, y: unit)

            // the shake (only the one dot that has the turn)
            if shaking {
                let p = (time / 0.6).truncatingRemainder(dividingBy: 1)
                let frames: [(Double, Double, Double, Double, Double, Double)] = [
                    (0, 0, 0, 0, 1, 1), (0.18, -1.2, 0.6, -amplitude, 1.02, 0.98), (0.36, 1.4, -0.8, amplitude, 0.98, 1.02),
                    (0.54, -0.8, -0.4, -0.6 * amplitude, 1.02, 0.99), (0.72, 1, 0.7, 0.8 * amplitude, 0.99, 1.01), (1, 0, 0, 0, 1, 1),
                ]
                let value = Self.sample(frames, p)
                context.translateBy(x: 50, y: 55)
                context.translateBy(x: value[0], y: value[1])
                context.rotate(by: .degrees(value[2]))
                context.scaleBy(x: value[3], y: value[4])
                context.translateBy(x: -50, y: -55)
            }

            context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.fill(path, with: .linearGradient(Gradient(colors: [light, dark]), startPoint: CGPoint(x: 20, y: 0), endPoint: CGPoint(x: 80, y: 100)))
            context.drawLayer { layer in
                layer.translateBy(x: 36, y: 30)
                layer.rotate(by: .degrees(-28))
                layer.fill(Path(ellipseIn: CGRect(x: -12, y: -6, width: 24, height: 12)), with: .color(Color.white.opacity(0.35)))
            }

            // the eyes: they look around slowly (down, up, aside, changing height) and blink
            let look = eye.scale * 3.4
            let lookPhase = ((time + lookShift) / lookPeriod).truncatingRemainder(dividingBy: 1)
            let lookFrames: [(Double, Double, Double, Double, Double, Double)] = [
                (0, 0, 0, 0, 1, 0), (0.18, 0, look * 1.6, 0, 1.12, 0), (0.38, -look, look * 0.6, 0, 0.92, 0),
                (0.58, look * 0.9, -look * 1.4, 0, 1.1, 0), (0.8, look, look * 0.4, 0, 0.95, 0), (1, 0, 0, 0, 1, 0),
            ]
            let looked = Self.sample(lookFrames, lookPhase < 0 ? lookPhase + 1 : lookPhase)
            let blinkPhase = ((time + blinkShift) / blinkPeriod).truncatingRemainder(dividingBy: 1)
            let blinkAt = blinkPhase < 0 ? blinkPhase + 1 : blinkPhase
            let blink: Double = blinkAt < 0.92 ? 1 : (blinkAt < 0.955 ? 1 - 0.92 * ((blinkAt - 0.92) / 0.035) : 0.08 + 0.92 * ((blinkAt - 0.955) / 0.045))
            let rx = 9 * eye.scale
            let ry = 13 * eye.scale
            let gap = 12 * eye.scale
            for side in [-1.0, 1.0] {
                context.drawLayer { layer in
                    layer.translateBy(x: 50 + side * gap + looked[0], y: eye.y + looked[1])
                    layer.scaleBy(x: 1, y: looked[3] * blink)
                    layer.fill(Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)), with: .color(.white))
                }
            }
        }
    }

    /// Smooth (ease in and out) blending between key frames: frames are (position, a, b, c, d, e); returns [a, b, c, d, e].
    private static func sample(_ frames: [(Double, Double, Double, Double, Double, Double)], _ phase: Double) -> [Double] {
        var previous = frames[0]
        for frame in frames.dropFirst() {
            if phase <= frame.0 {
                let span = max(0.0001, frame.0 - previous.0)
                let raw = (phase - previous.0) / span
                let t = raw * raw * (3 - 2 * raw)
                return [
                    previous.1 + (frame.1 - previous.1) * t, previous.2 + (frame.2 - previous.2) * t, previous.3 + (frame.3 - previous.3) * t,
                    previous.4 + (frame.4 - previous.4) * t, previous.5 + (frame.5 - previous.5) * t,
                ]
            }
            previous = frame
        }
        return [previous.1, previous.2, previous.3, previous.4, previous.5]
    }
}
