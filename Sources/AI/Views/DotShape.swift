import SwiftUI

/// The outlines dots come in. Every shape is centred on the origin, contains
/// its centre (so the eyes always sit inside) and fits inside a circle of the
/// given radius, so collisions and eating are the same whatever the shape.
/// The default dot is the circle; every paid style has a shape of its own.
enum DotShape: String, CaseIterable {
    case circle
    // stars
    case star5, star4, star6, star7, star8, burst12, softStar
    // petals and gears
    case flower3, flower4, flower5, flower6, flower8, gear6, gear8, gear10
    // straight-sided
    case triangle, diamond, pentagon, hexagon, heptagon, octagon, nonagon, decagon, kite, arrowhead
    // everything else
    case heart, drop, shield, plus, squircle, egg, leaf, cloud, lemon, bolt, pill, crown

    /// Every shape except the circle, in the order styles are given them.
    static let special: [DotShape] = allCases.filter { $0 != .circle }

    static func path(_ shape: DotShape, radius r: CGFloat) -> Path {
        func polygon(_ n: Int, _ rad: CGFloat, rotation: CGFloat = -.pi / 2) -> Path {
            var p = Path()
            for i in 0..<n {
                let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(n)
                let pt = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        }
        func star(_ points: Int, inner: CGFloat, outer: CGFloat = 1.04) -> Path {
            var p = Path()
            for i in 0..<(points * 2) {
                let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
                let rad = r * (i.isMultiple(of: 2) ? outer : inner)
                let pt = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        }
        func polar(_ steps: Int = 120, _ f: (CGFloat) -> CGFloat) -> Path {
            var p = Path()
            for i in 0...steps {
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi - .pi / 2
                let rad = f(a)
                let pt = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        }
        func gear(_ teeth: Int) -> Path {
            polar(teeth * 24) { a in
                // A smoothed square wave: flat tops and bottoms with short ramps.
                let wave = tanh(5 * sin(CGFloat(teeth) * (a + .pi / 2)))
                return r * (0.86 + 0.16 * wave * 0.5 + 0.0)
            }
        }
        func points(_ list: [(CGFloat, CGFloat)]) -> Path {
            var p = Path()
            for (i, c) in list.enumerated() {
                let pt = CGPoint(x: c.0 * r, y: c.1 * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        }

        switch shape {
        case .circle: return Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        case .star5: return star(5, inner: 0.5)
        case .star4: return star(4, inner: 0.42)
        case .star6: return star(6, inner: 0.58)
        case .star7: return star(7, inner: 0.62)
        case .star8: return star(8, inner: 0.68)
        case .burst12: return star(12, inner: 0.78)
        case .softStar: return polar { a in r * (0.78 + 0.2 * cos(5 * (a + .pi / 2))) }
        case .flower3: return polar { a in r * (0.78 + 0.2 * cos(3 * (a + .pi / 2))) }
        case .flower4: return polar { a in r * (0.8 + 0.2 * cos(4 * (a + .pi / 2))) }
        case .flower5: return polar { a in r * (0.82 + 0.18 * cos(5 * (a + .pi / 2))) }
        case .flower6: return polar { a in r * (0.84 + 0.17 * cos(6 * (a + .pi / 2))) }
        case .flower8: return polar { a in r * (0.88 + 0.13 * cos(8 * (a + .pi / 2))) }
        case .gear6: return gear(6)
        case .gear8: return gear(8)
        case .gear10: return gear(10)
        case .triangle: return polygon(3, r * 1.12).applying(CGAffineTransform(translationX: 0, y: r * 0.14))
        case .diamond: return points([(0, -1.08), (0.86, 0), (0, 1.08), (-0.86, 0)])
        case .pentagon: return polygon(5, r * 1.04)
        case .hexagon: return polygon(6, r * 1.02)
        case .heptagon: return polygon(7, r * 1.02)
        case .octagon: return polygon(8, r * 1.02, rotation: -.pi / 2 + .pi / 8)
        case .nonagon: return polygon(9, r * 1.02)
        case .decagon: return polygon(10, r * 1.02)
        case .kite: return points([(0, -1.1), (0.78, -0.18), (0, 1.0), (-0.78, -0.18)])
        case .arrowhead: return points([(0, -1.08), (0.95, 0.9), (0, 0.45), (-0.95, 0.9)])
        case .heart:
            var p = Path()
            let s = r / 17
            for i in 0...80 {
                let t = CGFloat(i) / 80 * 2 * .pi
                let x = 16 * pow(sin(t), 3)
                let y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
                let pt = CGPoint(x: x * s, y: y * s + r * 0.06)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        case .drop:
            var p = Path()
            p.move(to: CGPoint(x: 0, y: -r * 1.15))
            p.addCurve(to: CGPoint(x: 0, y: r), control1: CGPoint(x: r * 1.25, y: -r * 0.1), control2: CGPoint(x: r * 1.0, y: r))
            p.addCurve(to: CGPoint(x: 0, y: -r * 1.15), control1: CGPoint(x: -r * 1.0, y: r), control2: CGPoint(x: -r * 1.25, y: -r * 0.1))
            p.closeSubpath()
            return p
        case .shield:
            var p = Path()
            p.move(to: CGPoint(x: -r * 0.9, y: -r * 0.85))
            p.addLine(to: CGPoint(x: r * 0.9, y: -r * 0.85))
            p.addLine(to: CGPoint(x: r * 0.9, y: r * 0.1))
            p.addQuadCurve(to: CGPoint(x: 0, y: r * 1.1), control: CGPoint(x: r * 0.85, y: r * 0.8))
            p.addQuadCurve(to: CGPoint(x: -r * 0.9, y: r * 0.1), control: CGPoint(x: -r * 0.85, y: r * 0.8))
            p.closeSubpath()
            return p
        case .plus:
            let t = 0.42, l = 1.0
            return points([(-t, -l), (t, -l), (t, -t), (l, -t), (l, t), (t, t), (t, l), (-t, l), (-t, t), (-l, t), (-l, -t), (-t, -t)])
        case .squircle:
            return polar(96) { a in
                let c = abs(cos(a)), s = abs(sin(a))
                return r / pow(pow(c, 4) + pow(s, 4), 0.25) * 0.9
            }
        case .egg:
            return polar { a in
                // Wider at the bottom than at the top.
                let up = -sin(a)   // 1 at the top
                return r * (1.0 - 0.14 * up) * 0.98
            }.applying(CGAffineTransform(scaleX: 0.88, y: 1.08))
        case .leaf:
            var p = Path()
            p.move(to: CGPoint(x: -r * 0.95, y: r * 0.95))
            p.addCurve(to: CGPoint(x: r * 0.95, y: -r * 0.95), control1: CGPoint(x: -r * 0.95, y: -r * 0.55), control2: CGPoint(x: -r * 0.2, y: -r * 1.0))
            p.addCurve(to: CGPoint(x: -r * 0.95, y: r * 0.95), control1: CGPoint(x: r * 0.95, y: r * 0.55), control2: CGPoint(x: r * 0.2, y: r * 1.0))
            p.closeSubpath()
            return p
        case .cloud:
            return polar { a in r * (0.76 + 0.26 * abs(sin(2.5 * a))) }
        case .lemon:
            // A lens with pointed ends, left and right.
            var p = Path()
            p.move(to: CGPoint(x: -r * 1.05, y: 0))
            p.addCurve(to: CGPoint(x: r * 1.05, y: 0), control1: CGPoint(x: -r * 0.5, y: -r * 1.0), control2: CGPoint(x: r * 0.5, y: -r * 1.0))
            p.addCurve(to: CGPoint(x: -r * 1.05, y: 0), control1: CGPoint(x: r * 0.5, y: r * 1.0), control2: CGPoint(x: -r * 0.5, y: r * 1.0))
            p.closeSubpath()
            return p
        case .bolt:
            return points([(0.2, -1.1), (-0.78, 0.18), (-0.06, 0.18), (-0.24, 1.1), (0.8, -0.28), (0.06, -0.28)])
        case .crown: return points([(-0.95, 0.8), (-0.95, -0.55), (-0.45, 0.0), (0, -0.9), (0.45, 0.0), (0.95, -0.55), (0.95, 0.8)])
        case .pill:
            let w = r * 0.62, h = r * 1.06
            return Path(roundedRect: CGRect(x: -w, y: -h, width: w * 2, height: h * 2), cornerRadius: w)
        }
    }
}

extension DotStyle {
    /// The shape this style is drawn as: the default dot is round and every
    /// paid style has a shape of its own (no two share one).
    var shape: DotShape {
        guard self != .classic, let index = DotStyle.allCases.firstIndex(of: self) else { return .circle }
        let special = DotShape.special
        return special[(index - 1) % special.count]
    }
}
