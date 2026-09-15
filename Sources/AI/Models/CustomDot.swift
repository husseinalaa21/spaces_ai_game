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
