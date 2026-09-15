import SwiftUI
import UIKit

/// The shell that holds the game's three pages behind a single top banner:
/// Home, Spacechat AI (centre), and Messages.
///
/// The banner is one light-grey pill with three icons in it — no per-icon
/// background, no border; the selected one simply turns black while the
/// others sit muted. Switching slides the pages horizontally in whichever
/// direction the tab moved, so the three pages read as one strip rather than
/// as unrelated screens appearing in place.
struct GameHubView: View {
    @ObservedObject var player: PlayerState
    @ObservedObject var authState: AuthState
    @ObservedObject var sync: SpacechatSync
    var save: () -> Void
    let onPlay: () -> Void

    enum Tab: Int, CaseIterable, Identifiable {
        case home = 0
        case spacechatAI = 1
        case messages = 2
        var id: Int { rawValue }
    }

    /// Height of the top inset the banner has to sit below, read from the
    /// active window once rather than guessed at a fixed number — it differs
    /// between a Dynamic Island, a notch, and an older flat top.
    @MainActor static let bannerTopInset: CGFloat = {
        max(GameHubView.keyWindowInsets?.top ?? 0, 20) + 6
    }()

    /// Height of the home indicator strip at the bottom, for the same
    /// reason: the pages run under it, so anything tappable needs clearance.
    @MainActor static let homeIndicatorInset: CGFloat = {
        GameHubView.keyWindowInsets?.bottom ?? 0
    }()

    @MainActor private static var keyWindowInsets: UIEdgeInsets? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets
    }

    @State private var tab: Tab = .home
    /// Which way the last switch moved, so insertion and removal slide the
    /// same way. Recomputed on every change rather than derived inside the
    /// transition, which is evaluated too late to know where we came from.
    @State private var movingForward = true

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch tab {
                case .home:
                    MainMenuView(player: player, authState: authState, sync: sync,
                                 save: save, onPlay: onPlay)
                case .spacechatAI:
                    SpacechatAIView(authState: authState)
                case .messages:
                    MessagesView(authState: authState)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: movingForward ? .trailing : .leading),
                removal: .move(edge: movingForward ? .leading : .trailing)
            ))

            // The container ignores the safe area, so the banner has to
            // clear the status bar / Dynamic Island itself rather than
            // relying on an inset that is no longer applied.
            banner
                .padding(.top, GameHubView.bannerTopInset)
        }
        // The page fills the whole display — under the notch/Dynamic Island
        // at the top and under the home indicator at the bottom — instead of
        // stopping at the safe area and leaving bands at either end.
        //
        // `.clipped()` used to be here to contain a sliding page, but it
        // clips to the SAFE-AREA frame, which is exactly what cropped the
        // page back off those edges. The window clips the slide anyway.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea()
    }

    // MARK: - Banner

    private var banner: some View {
        HStack(spacing: 2) {
            tabButton(.home) {
                Image(systemName: "house.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
            tabButton(.spacechatAI) {
                SpacechatMark(size: 19, active: tab == .spacechatAI)
            }
            tabButton(.messages) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(white: 0.93), in: Capsule())
    }

    private func tabButton<Icon: View>(_ target: Tab, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            guard tab != target else { return }
            movingForward = target.rawValue > tab.rawValue
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                tab = target
            }
            HapticsManager.shared.impact(.light)
        } label: {
            icon()
                .foregroundColor(tab == target ? .black : .black.opacity(0.32))
                .frame(width: 54, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The Spacechat logo, drawn from its own source rather than shipped as a
/// PNG.
///
/// Transcribed cell for cell from `spacechat_vision/spacechat_pixel_logo.svg`
/// — a 4x4 pixel grid with the top-left quadrant empty, in the four brand
/// blues. Drawing it means it stays crisp at any size (the SVG itself is
/// `shape-rendering="crispEdges"`, so square cells are the design, not an
/// approximation) and needs no asset catalog entry.
///
/// `active` handles the banner's selected state: a brand logo shouldn't be
/// tinted flat black the way an SF Symbol is, so it keeps its real colours
/// when selected and flattens to grey when not.
struct SpacechatMark: View {
    var size: CGFloat = 18
    var active: Bool = true

    private struct Cell {
        let x: Int
        let y: Int
        let color: Color
        /// Grey level used when the tab isn't selected, chosen to preserve
        /// the logo's own light-to-dark structure.
        let mutedWhite: Double
    }

    private static let pale = Color(red: 204 / 255, green: 252 / 255, blue: 252 / 255)
    private static let cyan = Color(red: 36 / 255, green: 192 / 255, blue: 228 / 255)
    private static let blue = Color(red: 12 / 255, green: 150 / 255, blue: 216 / 255)
    private static let navy = Color(red: 0 / 255, green: 72 / 255, blue: 108 / 255)

    private static let cells: [Cell] = [
        Cell(x: 2, y: 0, color: pale, mutedWhite: 0.78), Cell(x: 3, y: 0, color: pale, mutedWhite: 0.78),
        Cell(x: 2, y: 1, color: cyan, mutedWhite: 0.62), Cell(x: 3, y: 1, color: pale, mutedWhite: 0.78),
        Cell(x: 0, y: 2, color: blue, mutedWhite: 0.48), Cell(x: 1, y: 2, color: blue, mutedWhite: 0.48),
        Cell(x: 2, y: 2, color: cyan, mutedWhite: 0.62), Cell(x: 3, y: 2, color: cyan, mutedWhite: 0.62),
        Cell(x: 0, y: 3, color: navy, mutedWhite: 0.34), Cell(x: 1, y: 3, color: blue, mutedWhite: 0.48),
        Cell(x: 2, y: 3, color: blue, mutedWhite: 0.48), Cell(x: 3, y: 3, color: cyan, mutedWhite: 0.62)
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let cell = canvasSize.width / 4
            for item in Self.cells {
                // Half a point of overlap: adjacent cells otherwise show
                // hairline seams between them at fractional sizes.
                let rect = CGRect(x: CGFloat(item.x) * cell,
                                  y: CGFloat(item.y) * cell,
                                  width: cell + 0.5,
                                  height: cell + 0.5)
                context.fill(Path(rect),
                             with: .color(active ? item.color : Color(white: item.mutedWhite)))
            }
        }
        .frame(width: size, height: size)
    }

}
