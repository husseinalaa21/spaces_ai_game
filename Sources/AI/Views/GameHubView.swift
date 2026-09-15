import SwiftUI

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

            banner
                .padding(.top, 8)
        }
        .background(Color.white.ignoresSafeArea())
        // Clipped so a page sliding in from off-screen never paints outside
        // the shell while it travels.
        .clipped()
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
