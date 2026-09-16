import SwiftUI
import CoreGraphics

/// A colour stored in a form that survives `Codable` round-trips.
///
/// SwiftUI's `Color` is not reliably `Codable`, so everything the Dot Studio
/// saves goes through this instead of storing `Color` directly.
struct PaintColor: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Reads components back out of a SwiftUI `Color` (via UIKit, the only
    /// way to get at them). Falls back to opaque mid-grey rather than
    /// trapping if a colour can't be resolved — e.g. a dynamic system colour.
    init(_ color: Color) {
        #if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))
        } else {
            self.init(r: 0.5, g: 0.5, b: 0.5, a: 1)
        }
        #else
        self.init(r: 0.5, g: 0.5, b: 0.5, a: 1)
        #endif
    }

    static let defaultBase = PaintColor(r: 41 / 255, g: 121 / 255, b: 255 / 255)
}

/// One freehand paint stroke.
///
/// Points are normalized to the dot's own radius: (0,0) is the centre and
/// 1 is one radius out, so the same saved art renders correctly at every
/// size — the 46pt picker swatch, the 88pt preview and the live game dot.
struct DotStroke: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var points: [CGPoint]
    var color: PaintColor
    /// Also a fraction of the radius, for the same reason.
    var width: Double
}

/// One SF Symbol stuck onto the dot. Position is normalized like `DotStroke`;
/// `scale` is a fraction of the radius.
struct DotSticker: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var symbol: String
    var position: CGPoint
    var scale: Double
    var color: PaintColor

    /// The symbols offered in the studio. All are filled SF Symbols that
    /// exist on iOS 16, the app's deployment target — an unavailable name
    /// renders as nothing at all, so this list is deliberately conservative.
    static let catalog: [String] = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill",
        "crown.fill", "sparkles", "moon.fill", "sun.max.fill", "cloud.fill",
        "drop.fill", "snowflake", "diamond.fill", "shield.fill", "gift.fill",
        "eye.fill", "pawprint.fill", "gamecontroller.fill", "music.note",
        "camera.fill", "airplane", "car.fill", "hare.fill", "tortoise.fill",
        "face.smiling.fill", "checkmark.seal.fill", "exclamationmark.triangle.fill",
        "smallcircle.filled.circle.fill"
    ]
}

/// A dot the player designed themselves in the Dot Studio.
///
/// Saved on the profile and rendered by `DotRenderer` in place of a
/// `DotStyle`. Kept deliberately small and value-typed so it encodes into
/// the existing save file without any special handling.
struct CustomDot: Codable, Equatable {
    var baseColor: PaintColor = .defaultBase
    var strokes: [DotStroke] = []
    var stickers: [DotSticker] = []

    /// True when nothing has been drawn or stuck on — used to decide whether
    /// the menu offers "Create" or "Edit", and to avoid equipping a dot that
    /// would look identical to the plain default.
    var isBlank: Bool { strokes.isEmpty && stickers.isEmpty }

    /// Caps kept modest on purpose: every stroke and sticker is re-drawn each
    /// frame inside the game loop, and the whole thing is encoded into the
    /// save file on every write.
    static let maxStrokes = 120
    static let maxStickers = 12
    /// Long strokes are thinned as they're drawn (see `DotStudioView`), so
    /// this is a hard ceiling rather than a normal case.
    static let maxPointsPerStroke = 240
}

struct NamedCustomDot: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var artwork: CustomDot
}

struct CustomUniverse: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var background: PaintColor
    var grid: PaintColor
    var stars: Bool
    var palette: WorldBackground.Palette {
        WorldBackground.Palette(background: background.color, line: grid.color, isCosmic: stars)
    }
}

/// AI output is data, never executable code. Bound geometry and allowlisted
/// symbols keep generated artwork within the same limits as Dot Studio.
struct SpacesGeneratedDesign: Decodable {
    var name: String
    var base: [Double]?
    var stickers: [Sticker]?
    var background: [Double]?
    var grid: [Double]?
    var stars: Bool?
    struct Sticker: Decodable {
        var symbol: String
        var x: Double
        var y: Double
        var scale: Double
        var color: [Double]
    }
    static func parse(_ response: String) throws -> SpacesGeneratedDesign {
        guard let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"), start <= end else {
            throw SpacechatService.ServiceError.unavailable("The AI didn't return a usable design. Try a more specific description.")
        }
        let data = Data(response[start...end].utf8)
        let design = try JSONDecoder().decode(Self.self, from: data)
        guard !design.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, design.name.count <= 60 else {
            throw SpacechatService.ServiceError.unavailable("The AI returned an invalid design name. Please try again.")
        }
        return design
    }
    private func color(_ components: [Double]?) throws -> PaintColor {
        guard let components, components.count == 3, components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw SpacechatService.ServiceError.unavailable("The AI returned invalid colors. Please try again.")
        }
        return PaintColor(r: components[0], g: components[1], b: components[2])
    }
    func dot() throws -> NamedCustomDot {
        var artwork = CustomDot(baseColor: try color(base))
        for item in (stickers ?? []).prefix(CustomDot.maxStickers) {
            guard DotSticker.catalog.contains(item.symbol), item.x.isFinite, item.y.isFinite, item.scale.isFinite else {
                throw SpacechatService.ServiceError.unavailable("The AI chose unsupported artwork. Please try again.")
            }
            artwork.stickers.append(DotSticker(symbol: item.symbol, position: CGPoint(x: max(-0.65, min(0.65, item.x)), y: max(-0.65, min(0.65, item.y))), scale: max(0.12, min(0.65, item.scale)), color: try color(item.color)))
        }
        // A base-color-only design is still equipable in the existing studio.
        if artwork.stickers.isEmpty {
            artwork.stickers = [DotSticker(symbol: "sparkles", position: CGPoint(x: -0.35, y: 0.3), scale: 0.3, color: PaintColor(r: 1, g: 1, b: 1))]
        }
        return NamedCustomDot(name: name, artwork: artwork)
    }
    func universe() throws -> CustomUniverse {
        CustomUniverse(name: name, background: try color(background), grid: try color(grid), stars: stars ?? false)
    }
}
