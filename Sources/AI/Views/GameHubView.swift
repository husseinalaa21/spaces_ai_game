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

    /// Owned here so the menu's paywall and Settings' subscription rows are
    /// the same StoreManager — two instances would mean two product loads and
    /// two transaction listeners racing each other.
    @ObservedObject private var store = StoreManager.shared
    @StateObject private var inbox = SpacesInbox()
    @StateObject private var agentsStore = AgentsStore()
    @ObservedObject private var folderStore = FolderStore.shared
    @ObservedObject private var topicStore = TopicStore.shared
    @ObservedObject private var workspaceStore = WorkspaceStore.shared
    @ObservedObject private var projectStore = ProjectStore.shared
    /// The team flow (collect a team, brief it, watch it work) and a saved project being reopened.
    @State private var showTeam = false
    @State private var openProject: Project?
    /// The old Home (store, rewards, cosmetics), reached from the Store dot on the map.
    @State private var showStore = false
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var tabSpace

    enum Tab: Int, CaseIterable, Identifiable {
        case home = 0
        case folders = 2
        case settings = 4
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

    /// The app opens on Home, the first page, where Play is. A match also comes back to Home.
    @MainActor static var openTab: Tab = .home
    @State private var tab: Tab = GameHubView.openTab
    /// The login page, opened from the "Log in" button on Home and Settings.
    /// Presented over the hub rather than by swapping `RootView`'s phase, so
    /// the player comes back to the same tab they left.
    @State private var showLogin = false
    /// Which way the last switch moved, so insertion and removal slide the
    /// same way. Recomputed on every change rather than derived inside the
    /// transition, which is evaluated too late to know where we came from.
    @State private var movingForward = true

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch tab {
                case .home:
                    AgentMapView(authState: authState, agents: agentsStore, folders: folderStore, topics: topicStore, workspaces: workspaceStore, projects: projectStore,
                                 onCollectTeam: { showTeam = true },
                                 onOpenProject: { openProject = $0 },
                                 onStore: { showStore = true },
                                 onLogin: { showLogin = true })
                case .folders:
                    FoldersView(folders: folderStore, agents: agentsStore, authState: authState, onLogin: { showLogin = true })
                case .settings:
                    SettingsPageView(player: player, authState: authState,
                                     sync: sync, store: store, save: save,
                                     onLogin: { showLogin = true })
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
        .ignoresSafeArea(.container)
        // Signing in changes `authState`, which `RootView` already watches to
        // adopt the Spacechat account, and which the inbox task below watches
        // to start Messages — so all this has to do on success is close.
        .fullScreenCover(isPresented: $showLogin) {
            SignInView(authState: authState,
                       onSignedIn: { showLogin = false },
                       onClose: { showLogin = false })
                .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $showStore) {
            StoreView(player: player, store: store, authState: authState, save: save)
                .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $showTeam) {
            TeamFlowView(agents: agentsStore, folders: folderStore, projects: projectStore, authState: authState,
                         workspace: workspaceStore.current,
                         onLogin: { showTeam = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showLogin = true } },
                         onClose: { showTeam = false })
        }
        .fullScreenCover(item: $openProject) { saved in
            TeamFlowView(agents: agentsStore, folders: folderStore, projects: projectStore, authState: authState,
                         workspace: workspaceStore.current, project: saved,
                         onLogin: { openProject = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showLogin = true } },
                         onClose: { openProject = nil })
        }
        .onChange(of: scenePhase) { _ in inbox.persist() }
        .onChange(of: inbox.incomingAlertID) { _ in HapticsManager.shared.impact(.light) }
        .onAppear {
            store.requiresSignIn = { authState.isGuest }
            // Set before any product load so a purchase redelivered at launch is credited rather than finished silently.
            store.grantPoints = { points in player.profile.points += points; save() }
        }
        .task {
            // Ask Apple what this account owns at launch, so members-only dots and bought looks are right from the start.
            await store.loadProduct()
            await store.refreshEntitlement()
            player.refreshPremium(subscribed: store.isSubscribed)
        }
        .task(id: authState.spacechatUsername) {
            inbox.configure(username: authState.spacechatUsername)
            if authState.spacechatUsername != nil { await inbox.refresh() }
        }
        .task(id: "\(authState.spacechatUsername ?? "")-\(scenePhase == .active)") {
            guard authState.spacechatUsername != nil, scenePhase == .active else { return }
            while !Task.isCancelled {
                await inbox.poll()
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
            }
        }

    }

    // MARK: - Banner

    private var banner: some View {
        HStack(spacing: 2) {
            tabButton(.home, label: "Home") {
                Image(systemName: "house.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
            tabButton(.folders, label: "Folders") {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            tabButton(.settings, label: "Settings") {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            // Frosted glass with a hairline edge, floating over the page, instead of a flat grey slab.
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.white.opacity(0.62))
            }
        }
        .overlay(Capsule().stroke(Color.black.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private func tabButton<Icon: View>(_ target: Tab, label: String, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            guard tab != target else { return }
            movingForward = target.rawValue > tab.rawValue
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                tab = target
            }
            HapticsManager.shared.impact(.light)
        } label: {
            ZStack {
                // The highlight slides from one tab to the next.
                if tab == target {
                    Capsule().fill(Color.black.opacity(0.09))
                        .matchedGeometryEffect(id: "tabHighlight", in: tabSpace)
                }
                icon()
                    .foregroundColor(tab == target ? .black : .black.opacity(0.34))
            }
            .frame(width: 46, height: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(tab == target ? .isSelected : [])
    }
}

/// The Spacechat logo — three solid circles in a line, each covering most of
/// the one behind it. This is the mark Spacechat itself uses for Spacechat AI
/// (`SpacechatCircleMark` in the Spacechat app's SpacechatKit), so the game's
/// AI tab and AI page show the same logo the AI has in Spacechat. The old 4x4
/// pixel grid this replaces is Spacechat's retired mark; Spacechat only keeps
/// its name (`SpacechatPixelLogo`) for existing call sites.
///
/// Drawn from the source geometry rather than shipped as an image: a 512
/// canvas, circle radius 182.86, centres 73.14 apart (the web client's
/// /cyrcle files). That keeps it crisp at any size and needs no asset entry.
/// The three circles span exactly `size` points across, front circle on the
/// left, so the mark can be dropped in wherever a square icon goes.
///
/// `active` handles the banner's selected state: a brand logo shouldn't be
/// tinted flat black the way an SF Symbol is, so it keeps its real colours
/// when selected and flattens to grey when not.
struct SpacechatMark: View {
    var size: CGFloat = 18
    var active: Bool = true

    // The brand blues, as in SpacechatCircleMark.
    private static let cyan = Color(red: 0.141, green: 0.753, blue: 0.894)
    private static let blue = Color(red: 0.047, green: 0.588, blue: 0.847)
    private static let darkBlue = Color(red: 0.000, green: 0.282, blue: 0.424)

    /// Grey levels used when the tab isn't selected, chosen to keep the
    /// logo's own light-to-dark structure (front circle lightest).
    private static let mutedCyan = Color(white: 0.62)
    private static let mutedBlue = Color(white: 0.48)
    private static let mutedDark = Color(white: 0.34)

    var body: some View {
        let diameter = size * 365.72 / 512
        let step = size * 73.14 / 512
        ZStack(alignment: .leading) {
            Circle().fill(active ? Self.darkBlue : Self.mutedDark)
                .frame(width: diameter, height: diameter)
                .offset(x: step * 2)
            Circle().fill(active ? Self.blue : Self.mutedBlue)
                .frame(width: diameter, height: diameter)
                .offset(x: step)
            Circle().fill(active ? Self.cyan : Self.mutedCyan)
                .frame(width: diameter, height: diameter)
        }
        .frame(width: size, height: size, alignment: .leading)
        .accessibilityHidden(true)
    }
}
