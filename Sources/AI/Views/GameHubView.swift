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
                SpacechatMark(size: 18)
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

/// The Spacechat pixel mark, drawn rather than shipped as an image: a 3x3
/// grid of squares with the centre one filled solid, echoing the pixel logo.
/// Tints with `foregroundColor` like an SF Symbol, so the banner's selected
/// and unselected states apply to it unchanged.
struct SpacechatMark: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { context, canvasSize in
            let cell = canvasSize.width / 3
            let inset = cell * 0.18
            for row in 0..<3 {
                for column in 0..<3 {
                    let isCentre = row == 1 && column == 1
                    let rect = CGRect(x: CGFloat(column) * cell + inset,
                                      y: CGFloat(row) * cell + inset,
                                      width: cell - inset * 2,
                                      height: cell - inset * 2)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: cell * 0.22),
                        with: .color(isCentre ? .primary : .primary.opacity(0.45))
                    )
                }
            }
        }
        .frame(width: size, height: size)
    }
}
