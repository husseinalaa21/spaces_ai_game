import SwiftUI

/// Every agent's picture: a shape and a face that belong to that agent alone.
/// The built-in agents have hand-picked looks; agents the person makes get one
/// worked out from their id, so it never changes. This is the one avatar used
/// everywhere an agent appears (Messages, Agents, Spacechat AI, chats).
struct AgentLook: Equatable {
    enum Face: Int, CaseIterable { case round, pixel, happy, glasses, wink, sleepy, wide, visor }

    let shape: DotShape
    let face: Face
    let hue: Double

    static func make(id: String, hue: Double) -> AgentLook {
        switch id {
        case "builtin-dots": return AgentLook(shape: .circle, face: .round, hue: hue)
        case "builtin-coder": return AgentLook(shape: .hexagon, face: .visor, hue: hue)
        case "builtin-writer": return AgentLook(shape: .leaf, face: .happy, hue: hue)
        case "builtin-reviewer": return AgentLook(shape: .shield, face: .glasses, hue: hue)
        default:
            // FNV-1a: stable across launches, unlike Swift's seeded hashValue.
            var h: UInt64 = 0xcbf29ce484222325
            for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            let shapes = DotShape.special
            let shape = shapes[Int(h % UInt64(shapes.count))]
            let face = Face.allCases[Int((h >> 24) % UInt64(Face.allCases.count))]
            return AgentLook(shape: shape, face: face, hue: hue)
        }
    }
}

struct AgentAvatar: View {
    let id: String
    let hue: Double
    var size: CGFloat = 40

    init(agent: SpacesAgent, size: CGFloat = 40) { self.init(id: agent.id, hue: agent.hue, size: size) }
    init(id: String, hue: Double, size: CGFloat = 40) { self.id = id; self.hue = hue; self.size = size }

    /// Looks up an agent by the name other parts of the app use for it.
    init(name: String, in agents: [SpacesAgent], size: CGFloat = 40) {
        let match = agents.first { $0.name.lowercased() == name.lowercased() }
        self.init(id: match?.id ?? "name-" + name, hue: match?.hue ?? 0.6, size: size)
    }

    var body: some View {
        let look = AgentLook.make(id: id, hue: hue)
        let light = Color(hue: look.hue, saturation: 0.42, brightness: 1.0)
        let mid = Color(hue: look.hue, saturation: 0.7, brightness: 0.96)
        let dark = Color(hue: look.hue, saturation: 0.85, brightness: 0.62)
        ZStack {
            Canvas { ctx, s in
                let r = min(s.width, s.height) / 2 - size * 0.04
                let path = DotShape.path(look.shape, radius: r).offsetBy(dx: s.width / 2, dy: s.height / 2)
                ctx.fill(path, with: .linearGradient(Gradient(colors: [light, mid]),
                                                     startPoint: CGPoint(x: s.width * 0.25, y: 0),
                                                     endPoint: CGPoint(x: s.width * 0.8, y: s.height)))
                ctx.stroke(path, with: .color(dark), style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineJoin: .round))
            }
            face(look.face, ink: Color(white: 0.1))
                .frame(width: size * 0.62, height: size * 0.4)
                .offset(y: size * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func face(_ face: AgentLook.Face, ink: Color) -> some View {
        let e = size * 0.12
        switch face {
        case .round:
            HStack(spacing: size * 0.14) {
                Capsule().fill(Color.white).frame(width: e * 0.9, height: e * 1.7)
                Capsule().fill(Color.white).frame(width: e * 0.9, height: e * 1.7)
            }
        case .pixel:
            HStack(spacing: size * 0.14) {
                Rectangle().fill(ink).frame(width: e, height: e)
                Rectangle().fill(ink).frame(width: e, height: e)
            }
        case .happy:
            HStack(spacing: size * 0.12) {
                Arc(up: true).stroke(ink, style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round)).frame(width: e * 1.4, height: e * 0.9)
                Arc(up: true).stroke(ink, style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round)).frame(width: e * 1.4, height: e * 0.9)
            }
        case .glasses:
            HStack(spacing: size * 0.04) {
                Circle().stroke(ink, lineWidth: max(1.5, size * 0.05)).frame(width: e * 1.9, height: e * 1.9)
                Circle().stroke(ink, lineWidth: max(1.5, size * 0.05)).frame(width: e * 1.9, height: e * 1.9)
            }
        case .wink:
            HStack(spacing: size * 0.14) {
                Circle().fill(ink).frame(width: e * 1.2, height: e * 1.2)
                Arc(up: true).stroke(ink, style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round)).frame(width: e * 1.4, height: e * 0.9)
            }
        case .sleepy:
            HStack(spacing: size * 0.14) {
                Capsule().fill(ink).frame(width: e * 1.5, height: max(1.5, size * 0.045))
                Capsule().fill(ink).frame(width: e * 1.5, height: max(1.5, size * 0.045))
            }
        case .wide:
            HStack(spacing: size * 0.1) {
                ZStack { Circle().fill(Color.white); Circle().fill(ink).frame(width: e * 0.8, height: e * 0.8) }.frame(width: e * 1.8, height: e * 1.8)
                ZStack { Circle().fill(Color.white); Circle().fill(ink).frame(width: e * 0.8, height: e * 0.8) }.frame(width: e * 1.8, height: e * 1.8)
            }
        case .visor:
            RoundedRectangle(cornerRadius: e * 0.5, style: .continuous).fill(ink)
                .frame(width: size * 0.5, height: e * 1.5)
                .overlay(HStack(spacing: size * 0.1) {
                    Rectangle().fill(Color.white).frame(width: e * 0.7, height: e * 0.7)
                    Rectangle().fill(Color.white).frame(width: e * 0.7, height: e * 0.7)
                })
        }
    }
}

private struct Arc: Shape {
    var up: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: up ? rect.minY - rect.height * 0.4 : rect.maxY + rect.height))
        return p
    }
}
