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
    /// Small avatars in long lists stay still (they would cost a frame loop each); the bigger ones look around, blink and shake.
    var animated: Bool? = nil

    init(agent: SpacesAgent, size: CGFloat = 40, animated: Bool? = nil) { self.init(id: agent.id, hue: agent.hue, size: size, animated: animated) }
    init(id: String, hue: Double, size: CGFloat = 40, animated: Bool? = nil) { self.id = id; self.hue = hue; self.size = size; self.animated = animated }

    /// Looks up an agent by the name other parts of the app use for it.
    init(name: String, in agents: [SpacesAgent], size: CGFloat = 40) {
        let match = agents.first { $0.name.lowercased() == name.lowercased() }
        self.init(id: match?.id ?? "name-" + name, hue: match?.hue ?? 0.6, size: size)
    }

    /// The built-in agents keep their own shape; any other agent's is worked out from its id, the same way the Spacechat app does it.
    private var shape: String? {
        switch id {
        case "builtin-dots": return "circle"
        case "builtin-coder": return "hexagon"
        case "builtin-writer": return "flower"
        case "builtin-reviewer": return "squircle"
        default: return nil
        }
    }

    var body: some View {
        SpacechatDotFace(key: id, size: size, animated: animated ?? (size >= 40), hue: hue * 360, shape: shape)
    }
}
