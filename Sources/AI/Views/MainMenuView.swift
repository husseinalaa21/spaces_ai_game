import SwiftUI
import AuthenticationServices

/// A subtle "press" feel for buttons that don't already animate their own
/// state — scales down and dims slightly while held, springs back on
/// release. Applied across the main menu and Store so every tap reads as
/// acknowledged instead of the label just instantly changing.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// One accent color per small icon (§ new — icons used to be uniformly gold
/// on a tinted circle; now each carries its own hue and sits directly on the
/// surface with no shape behind it, so the icon itself does the work).
enum IconPalette {
    static let blue   = Color(red: 0.16, green: 0.47, blue: 1.00)
    static let teal   = Color(red: 0.08, green: 0.70, blue: 0.74)
    static let green  = Color(red: 0.13, green: 0.70, blue: 0.42)
    static let gold   = Color(red: 0.90, green: 0.68, blue: 0.11)
    static let orange = Color(red: 0.97, green: 0.55, blue: 0.13)
    static let pink   = Color(red: 0.95, green: 0.35, blue: 0.60)
    static let purple = Color(red: 0.58, green: 0.35, blue: 0.94)

    /// Colors for the 7-day reward ladder, one per day.
    static let ladder: [Color] = [blue, teal, green, gold, orange, pink, purple]
}

/// Shown right after sign-in (or straight after the splash screen, for a
/// returning player), before White Space actually starts. An animated
/// preview of the player dot — the same blue as the app's own logo dot, no
/// card/background around it — two small cosmetic pickers (Universe, Dot
/// Style — §27-29's AI+ premium store, MVP'd locally per §87), and a single
/// Play button at the bottom. White Space itself only starts once the
/// player taps Play (`RootView` doesn't build the world until then).
struct MainMenuView: View {
    @ObservedObject var player: PlayerState
    @ObservedObject var authState: AuthState
    @ObservedObject var sync: SpacechatSync
    var save: () -> Void = {}
    let onPlay: () -> Void

    /// Owned here and handed down to every screen that sells Premium, so
    /// there's exactly one product load and one transaction listener for the
    /// whole session.
    @StateObject private var store = StoreManager()

    @State private var showDotStudio = false
    @State private var showPremiumSheet = false
    @State private var showStore = false
    @State private var showDailyReward = false
    @State private var showRenameSheet = false
    @State private var hasAppeared = false
    /// Set when the player taps a locked Universe/Dot Style they don't yet
    /// own (§ new — individually-priced cosmetics) — drives `CosmeticPurchaseSheet`.
    @State private var purchaseTarget: CosmeticPurchase? = nil
    /// "View More" under each picker (§ new — "add view more button under
    /// them to let it view more dots or more universes") opens the full
    /// catalog as a browsable grid, where tapping any tile just previews it
    /// up top without committing anything — a separate Equip/Buy button
    /// there is what actually changes the saved selection or spends Points.
    @State private var browseKind: CosmeticBrowseSheet.Kind? = nil

    var body: some View {
        ZStack {
            // A very faint radial tint instead of flat white — just enough
            // depth that the page doesn't feel like a blank sheet, without
            // adding any actual clutter (§41).
            RadialGradient(colors: [Color(white: 0.99), Color(white: 0.94)],
                           center: .center, startRadius: 40, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                // No more "Spaces" wordmark above the preview (§ user
                // feedback) — the animated dot cluster itself is the header
                // now, the same way the app icon carries the brand with no
                // name printed next to it. What sits there instead is the
                // player's own handle (§ new — "add in the home page ability
                // to let the user change his name"), the same "davi_32"-style
                // name shown under every dot in the universe, tappable to
                // rename right here rather than buried in Settings.
                Button {
                    showRenameSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Text(player.profile.username ?? "")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.97))

                ZStack {
                    // AI+ dot styles get a few slow orbiting sparkles around
                    // the preview so a premium pick visibly reads as more
                    // special right on the menu, not just once in a round.
                    if player.profile.selectedDotStyle.isPremium {
                        OrbitingSparkles(color: player.profile.selectedDotStyle.swatchColor,
                                          reduceMotion: player.profile.reduceMotion)
                    }
                    PlayPreviewDot(
                        reduceMotion: player.profile.reduceMotion,
                        dotStyle: player.profile.selectedDotStyle,
                        customDot: player.activeCustomDot,
                        isUnlocked: { player.profile.owns($0) },
                        onSelectStyle: { player.profile.selectedDotStyle = $0; save() },
                        onLockedTap: { purchaseTarget = .dotStyle($0) }
                    )
                }

                Text(player.profile.selectedDotStyle.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.4))

                viewMoreButton { browseKind = .dotStyles }

                // Dot Style is now switched directly from the preview above
                // (tap the blurred dot to its left/right) instead of its own
                // swatch row — only Universe still uses a picker row, now
                // `UniversePickerRow`'s richer preview tiles (a mini
                // screenshot of each universe's real background) instead of
                // the old plain circular swatches.
                HStack(alignment: .top, spacing: 28) {
                    UniversePickerRow(
                        options: Array(UniverseTheme.allCases),
                        selection: Binding(
                            get: { player.profile.selectedUniverse },
                            set: { player.profile.selectedUniverse = $0; save() }
                        ),
                        isUnlocked: { player.profile.owns($0) },
                        onLockedTap: { purchaseTarget = .universe($0) }
                    )
                }
                .padding(.horizontal, 24)

                viewMoreButton { browseKind = .universes }

                Spacer()

                Button { showDotStudio = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(player.profile.customDot.isBlank ? "Customize Dot" : "Edit My Dot")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(width: 220, height: 48)
                }
                .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 1.5))
                .clipShape(Capsule())
                .buttonStyle(PressableButtonStyle())
                .padding(.bottom, 12)

                Button(action: onPlay) {
                    Text("Play")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 220, height: 54)
                }
                .background(Color.black)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .buttonStyle(PressableButtonStyle())
                .padding(.bottom, 40)
            }
            // Starts below the banner rather than at the top of the display.
            // The column's leading Spacer only distributes leftover space, so
            // on a short screen the username row underneath it was sliding up
            // behind the Home/AI/Messages banner.
            .padding(.top, GameHubView.bannerTopInset + 46)
            // And clear of the home indicator at the other end, now that the
            // page runs underneath it.
            .padding(.bottom, GameHubView.homeIndicatorInset)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)

            VStack {
                HStack(alignment: .top, spacing: 10) {
                    storeButton
                    dailyRewardButton
                    Spacer()
                    pointsBadge
                }
                .padding(.horizontal, 16)
                // Sits just under the banner. Derived from the device's real
                // top inset, not a fixed number — that would tuck the Store
                // button under the banner on a Dynamic Island phone and leave
                // a gap on an older one.
                .padding(.top, GameHubView.bannerTopInset + 52)
                Spacer()
            }
            .opacity(hasAppeared ? 1 : 0)
        }
        .onAppear {
            // A quiet fade + rise on first appearance (skipped entirely
            // under Reduce Motion) — landing on the menu feels like arriving
            // somewhere rather than the UI just being instantly present.
            if player.profile.reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.5)) { hasAppeared = true }
            }
        }
        // Ask Apple what this Apple ID actually owns, every time the menu
        // appears — a subscription can be cancelled, lapse, be refunded or be
        // bought on another device entirely outside this app.
        .task {
            // Set before any product load so a transaction redelivered at
            // launch (a crash mid-purchase, a late Ask to Buy approval) is
            // credited rather than finished silently.
            store.grantPoints = { points in
                player.profile.points += points
                save()
            }
            await store.loadProduct()
            await store.refreshEntitlement()
            player.refreshPremium(subscribed: store.isSubscribed)
            save()
        }
        .onChange(of: store.isSubscribed) { subscribed in
            player.refreshPremium(subscribed: subscribed)
            save()
        }
        .sheet(isPresented: $showDotStudio) {
            DotStudioView(player: player, save: save)
        }
        .sheet(isPresented: $showPremiumSheet) {
            PremiumUnlockSheet(store: store, player: player, authState: authState, save: save) {
                showPremiumSheet = false
            }
        }
        .sheet(isPresented: $showStore) {
            StoreView(player: player, store: store, authState: authState, save: save)
        }
        .sheet(isPresented: $showDailyReward) {
            DailyRewardSheet(player: player, save: save)
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(currentName: player.profile.username ?? "") { newName in
                player.profile.username = newName
                save()
            }
        }
        .sheet(item: $purchaseTarget) { purchase in
            CosmeticPurchaseSheet(
                purchase: purchase,
                player: player,
                onBuy: { buy(purchase) },
                onGetPremium: {
                    purchaseTarget = nil
                    showPremiumSheet = true
                }
            )
        }
        .sheet(item: $browseKind) { kind in
            CosmeticBrowseSheet(
                kind: kind,
                player: player,
                save: save,
                onGetPremium: {
                    browseKind = nil
                    showPremiumSheet = true
                }
            )
        }
    }

    /// A small, quiet text button under each picker (§ new — "add view more
    /// button under them") opening the full catalog as a browsable grid.
    private func viewMoreButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("View More")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.black.opacity(0.4))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96))
    }

    /// Spends Points to unlock a single locked Universe or Dot Style (see
    /// `CosmeticPurchaseSheet`) — a no-op if the player can't actually
    /// afford it, so the "Buy" button there is already disabled in that case.
    private func buy(_ purchase: CosmeticPurchase) {
        let bought: Bool
        switch purchase {
        case .universe(let theme): bought = player.purchase(theme)
        case .dotStyle(let style): bought = player.purchase(style)
        }
        guard bought else { return }
        save()
        HapticsManager.shared.success()
        purchaseTarget = nil
    }

    // MARK: - Store / Points (top bar)

    private var storeButton: some View {
        Button(action: { showStore = true }) {
            Image(systemName: "bag.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.black.opacity(0.75))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// Opens `DailyRewardSheet`; a small dot badges the icon whenever a
    /// reward is waiting to be claimed (§ new — a plain gift icon by itself
    /// gives no reason to ever tap it, so the badge is what actually invites
    /// the tap on the days it matters).
    private var dailyRewardButton: some View {
        Button(action: { showDailyReward = true }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.black.opacity(0.75))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                if player.canClaimDailyReward {
                    Circle()
                        .fill(Color(red: 0.9, green: 0.28, blue: 0.24))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var pointsBadge: some View {
        Button(action: { showStore = true }) {
            HStack(spacing: 5) {
                Image("Sparkle")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 13, height: 13)
                    .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.13))
                Text(formattedPoints)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.8))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: player.profile.points)
    }

    private var formattedPoints: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: player.profile.points)) ?? "\(player.profile.points)"
    }
}

/// Universe picker: rounded-square tiles that actually look like a tiny
/// screenshot of that universe (same background/grid `WorldBackground`
/// draws in-game, plus a couple of small "icon" dots) instead of a flat
/// color swatch. Shows only three at a time — previous / selected (center,
/// bigger) / next — rather than laying out every option in one row, so this
/// keeps working cleanly now that the catalog has grown well past three
/// (§ new — "add more universes to buy"); tapping a side tile cycles the
/// selection, mirroring the Dot Style preview's own prev/next carousel feel
/// (`PlayPreviewDot` below uses the exact same modulo-index approach).
private struct UniversePickerRow: View {
    let options: [UniverseTheme]
    @Binding var selection: UniverseTheme
    let isUnlocked: (UniverseTheme) -> Bool
    let onLockedTap: (UniverseTheme) -> Void

    private var index: Int { options.firstIndex(of: selection) ?? 0 }
    private var previous: UniverseTheme { options[(index - 1 + options.count) % options.count] }
    private var next: UniverseTheme { options[(index + 1) % options.count] }

    var body: some View {
        VStack(spacing: 8) {
            Text("UNIVERSE")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.black.opacity(0.45))

            HStack(spacing: 18) {
                sideTile(previous)
                centerTile
                sideTile(next)
            }
            .padding(.top, 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selection)

            Text(selection.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.black.opacity(0.35))
        }
    }

    private var centerTile: some View {
        UniverseSwatch(theme: selection, isSelected: true, locked: false)
    }

    private func sideTile(_ theme: UniverseTheme) -> some View {
        Button {
            select(theme)
        } label: {
            UniverseSwatch(theme: theme, isSelected: false, locked: !isUnlocked(theme))
        }
        .buttonStyle(.plain)
    }

    private func select(_ theme: UniverseTheme) {
        if isUnlocked(theme) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selection = theme
            }
        } else {
            onLockedTap(theme)
        }
    }
}

/// A single Universe preview tile — a rounded-square "screenshot" of that
/// universe's actual `WorldBackground` palette (same background fill + grid
/// color used in-game) with a few small colored dots standing in for the
/// rival dots you'd see floating in it, so the home page picker reads as a
/// tiny window into each universe rather than an abstract color chip.
private struct UniverseSwatch: View {
    let theme: UniverseTheme
    let isSelected: Bool
    let locked: Bool

    private var palette: WorldBackground.Palette { WorldBackground.palette(for: theme) }
    private var size: CGFloat { isSelected ? 64 : 50 }

    /// The two showiest universes get a ring — it's the single strongest cue
    /// that these are planets and not just coloured circles, so it's spent on
    /// the ones worth drawing attention to rather than on all nine.
    private var hasRing: Bool { theme == .cosmic || theme == .aurora }

    /// Surface colour. `.white`'s own swatch is pure white, which would
    /// vanish against the menu, so it borrows its grid line colour instead.
    private var surface: Color {
        theme == .white ? Color(red: 0.86, green: 0.88, blue: 0.92) : theme.swatchColor
    }

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                draw(context, canvasSize: canvasSize)
            }
            .frame(width: size, height: size)

            if locked {
                Circle().fill(Color.black.opacity(0.45))
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            } else if isSelected {
                Circle()
                    .stroke(Color.white, lineWidth: 2.5)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .offset(x: size / 2 - 8, y: -(size / 2) + 8)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isSelected ? 1.0 : 0.92)
        .opacity(isSelected ? 1.0 : 0.75)
    }

    /// Draws the planet: ring behind, globe, surface bands, day/night
    /// terminator, specular highlight, then the front arc of the ring.
    ///
    /// Everything is proportional to the canvas, so the same code serves the
    /// 50pt unselected swatch and the 64pt selected one.
    private func draw(_ context: GraphicsContext, canvasSize: CGSize) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        // Leaves room for the ring and the atmosphere glow to sit inside the
        // frame instead of being clipped by it.
        let radius = min(canvasSize.width, canvasSize.height) * 0.38
        let globe = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2))

        // Light comes from the top-right, the same direction the dots and the
        // app icon use.
        let lightOffset = CGPoint(x: center.x + radius * 0.42, y: center.y - radius * 0.42)

        let ringPath: Path? = hasRing ? ringEllipse(center: center, radius: radius) : nil

        // --- ring, back half (the globe is drawn over it next) -------------
        if let ringPath {
            var back = context
            back.opacity = 0.55
            back.stroke(ringPath, with: .color(surface.mix(with: .white, amount: 0.45)),
                        lineWidth: max(1, radius * 0.11))
        }

        // --- atmosphere -----------------------------------------------------
        var glow = context
        glow.opacity = 0.35
        glow.addFilter(.blur(radius: radius * 0.22))
        glow.fill(
            Path(ellipseIn: CGRect(x: center.x - radius * 1.12, y: center.y - radius * 1.12,
                                    width: radius * 2.24, height: radius * 2.24)),
            with: .color(surface)
        )

        // --- globe ----------------------------------------------------------
        context.fill(
            globe,
            with: .radialGradient(
                Gradient(colors: [
                    surface.mix(with: .white, amount: 0.55),
                    surface,
                    surface.mix(with: .black, amount: 0.42)
                ]),
                center: lightOffset,
                startRadius: 0,
                endRadius: radius * 1.9
            )
        )

        // --- surface bands ---------------------------------------------------
        // Flattened arcs across the globe read as latitude lines on a sphere.
        // Offsets are fixed per theme, so a swatch never jitters between
        // renders the way anything random would.
        var surfaceContext = context
        surfaceContext.clip(to: globe)
        // Derived from the theme's position in the catalog, NOT from
        // hashValue: String hashing is randomly seeded per process in Swift,
        // so that would give each universe a different surface on every
        // launch.
        let index = UniverseTheme.allCases.firstIndex(of: theme) ?? 0
        let seed = Double(index % 7) / 7.0
        for i in 0..<3 {
            let t = (Double(i) + 0.5) / 3.0
            let y = center.y + CGFloat((t - 0.5 + (seed - 0.5) * 0.25) * 1.7) * radius
            let halfWidth = radius * CGFloat(0.95 - abs(t - 0.5) * 0.7)
            let height = radius * CGFloat(0.20 + seed * 0.12)
            surfaceContext.opacity = 0.16
            surfaceContext.fill(
                Path(ellipseIn: CGRect(x: center.x - halfWidth, y: y - height / 2,
                                        width: halfWidth * 2, height: height)),
                with: .color(i % 2 == 0 ? Color.white : palette.line)
            )
        }

        // --- night side -------------------------------------------------------
        // A soft crescent opposite the light, which is what actually makes a
        // flat circle read as a sphere.
        var night = context
        night.clip(to: globe)
        night.opacity = 0.34
        night.addFilter(.blur(radius: radius * 0.3))
        night.fill(
            Path(ellipseIn: CGRect(x: center.x - radius * 1.75, y: center.y - radius * 0.65,
                                    width: radius * 2.2, height: radius * 2.2)),
            with: .color(.black)
        )

        // --- specular highlight ------------------------------------------------
        var shine = context
        shine.clip(to: globe)
        shine.opacity = 0.5
        shine.addFilter(.blur(radius: radius * 0.16))
        let shineRadius = radius * 0.34
        shine.fill(
            Path(ellipseIn: CGRect(x: lightOffset.x - shineRadius, y: lightOffset.y - shineRadius,
                                    width: shineRadius * 2, height: shineRadius * 2)),
            with: .color(.white)
        )

        // --- limb --------------------------------------------------------------
        context.stroke(globe, with: .color(surface.mix(with: .black, amount: 0.35).opacity(0.35)),
                       lineWidth: max(0.5, radius * 0.05))

        // --- ring, front half ----------------------------------------------------
        // Clipped to below the ring's centre line so it crosses in front of
        // the globe, which is what sells the ring as encircling it.
        if let ringPath {
            var front = context
            front.clip(to: Path(CGRect(x: 0, y: center.y, width: canvasSize.width,
                                        height: canvasSize.height - center.y)))
            front.opacity = 0.9
            front.stroke(ringPath, with: .color(surface.mix(with: .white, amount: 0.55)),
                         lineWidth: max(1, radius * 0.11))
        }
    }

    /// The ring, tilted so it reads as a disc seen at an angle rather than a
    /// flat halo drawn around the globe.
    private func ringEllipse(center: CGPoint, radius: CGFloat) -> Path {
        let rect = CGRect(x: center.x - radius * 1.5, y: center.y - radius * 0.42,
                           width: radius * 3.0, height: radius * 0.84)
        return Path(ellipseIn: rect).applying(
            CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(rotationAngle: -0.28))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        )
    }
}

/// A static single-frame render of the REAL in-game dot for a given Dot
/// Style — the actual `DotRenderer.drawPlayer` output (liquid body shape,
/// glossy gradient shading, ambient glow, eyes, worn hat, and worn clothing
/// accessory) instead of a simplified hand-drawn circle+icon. Used by every
/// shop/browse tile so what the player sees while shopping always matches
/// what they'll actually see equipped (§ user feedback: "the style of the
/// dots needs more work"). `time: 0` plus `reduceMotion: true` freezes the
/// idle wobble/blink/sweep at a clean resting frame — plenty for a thumbnail.
private struct DotStylePreviewCanvas: View {
    let style: DotStyle
    var diameter: CGFloat = 46

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = diameter * 0.28
            DotRenderer.drawPlayer(
                context, center: center, radius: radius,
                color: DotStyle.classic.swatchColor,
                stretch: 0, angle: .zero, lookDirection: .zero, time: 0,
                eyeStyle: .whiteOnly, reduceMotion: true, eatPulse: 0,
                dotStyle: style
            )
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Identifies a single locked Universe or Dot Style the player just tapped
/// (§ new — individually-priced cosmetics), so one `CosmeticPurchaseSheet`
/// can serve both pickers instead of writing it twice.
private enum CosmeticPurchase: Identifiable, Equatable {
    case universe(UniverseTheme)
    case dotStyle(DotStyle)

    var id: String {
        switch self {
        case .universe(let theme): return "universe_\(theme.rawValue)"
        case .dotStyle(let style): return "dotStyle_\(style.rawValue)"
        }
    }

    var name: String {
        switch self {
        case .universe(let theme): return theme.displayName
        case .dotStyle(let style): return style.displayName
        }
    }

    var price: Int {
        switch self {
        case .universe(let theme): return theme.price
        case .dotStyle(let style): return style.price
        }
    }
}

/// Shown when tapping a locked Universe or Dot Style that isn't covered by
/// AI+ Premium — buy just that one item with Points, or jump straight to
/// AI+ for everything at once. Exactly like `PremiumUnlockSheet` and
/// `StoreView`, no real payment is taken here — buying only spends the
/// player's own saved Points.
private struct CosmeticPurchaseSheet: View {
    let purchase: CosmeticPurchase
    @ObservedObject var player: PlayerState
    var onBuy: () -> Void
    var onGetPremium: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var canAfford: Bool { player.profile.points >= purchase.price }
    private let gold = DotStyle.gold.swatchColor

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.black.opacity(0.15))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            previewView
                .frame(width: 90, height: 90)

            Text(purchase.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            HStack(spacing: 6) {
                Image("Sparkle").renderingMode(.template).resizable()
                    .frame(width: 16, height: 16).foregroundColor(gold)
                Text("\(purchase.price)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.black.opacity(0.75))

            Button(action: onBuy) {
                Text(canAfford ? "Buy for \(purchase.price) Points" : "Not enough Points")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(canAfford ? Color.black : Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
            .buttonStyle(PressableButtonStyle())
            .disabled(!canAfford)
            .padding(.horizontal, 24)

            Button(action: onGetPremium) {
                Text("Or unlock everything with Premium")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .presentationDetents([.height(360)])
    }

    @ViewBuilder private var previewView: some View {
        switch purchase {
        case .universe(let theme):
            UniverseSwatch(theme: theme, isSelected: true, locked: false)
        case .dotStyle(let style):
            DotStylePreviewCanvas(style: style, diameter: 74)
        }
    }
}

/// The full catalog for Universes or Dot Styles, reachable via "View More"
/// under either picker on the main menu (§ new — "add view more button
/// under them to let it view more dots or more universes"). Tapping any
/// tile in the grid — owned or not — just changes the big preview up top
/// ("let user able to change the dot or universe as preview"); a separate
/// Equip/Buy button there is what actually changes the player's saved
/// selection or spends Points, so freely browsing never commits anything.
private struct CosmeticBrowseSheet: View {
    enum Kind: Identifiable {
        case universes, dotStyles
        var id: Self { self }
    }

    let kind: Kind
    @ObservedObject var player: PlayerState
    var save: () -> Void
    var onGetPremium: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var previewUniverse: UniverseTheme
    @State private var previewDotStyle: DotStyle

    init(kind: Kind, player: PlayerState, save: @escaping () -> Void, onGetPremium: @escaping () -> Void) {
        self.kind = kind
        self.player = player
        self.save = save
        self.onGetPremium = onGetPremium
        _previewUniverse = State(initialValue: player.profile.selectedUniverse)
        _previewDotStyle = State(initialValue: player.profile.selectedDotStyle)
    }

    private var title: String { kind == .universes ? "Universes" : "Dot Styles" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    previewHeader

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 16) {
                        switch kind {
                        case .universes: universeTiles
                        case .dotStyles: dotStyleTiles
                        }
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)

                    Button(action: onGetPremium) {
                        Text("Unlock everything with Premium")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
            }
            .background(Color(white: 0.96).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Preview header (updates on tap, commits nothing by itself)

    @ViewBuilder private var previewHeader: some View {
        switch kind {
        case .universes:
            previewCard(name: previewUniverse.displayName,
                        owned: player.profile.owns(previewUniverse),
                        equipped: player.profile.selectedUniverse == previewUniverse,
                        price: previewUniverse.price,
                        onEquip: { player.profile.selectedUniverse = previewUniverse; save() },
                        onBuy: { if player.purchase(previewUniverse) { save(); HapticsManager.shared.success() } }) {
                UniverseSwatch(theme: previewUniverse, isSelected: true, locked: false)
                    .scaleEffect(1.3)
            }
        case .dotStyles:
            previewCard(name: previewDotStyle.displayName,
                        owned: player.profile.owns(previewDotStyle),
                        equipped: player.profile.selectedDotStyle == previewDotStyle,
                        price: previewDotStyle.price,
                        plain: true,
                        onEquip: { player.profile.selectedDotStyle = previewDotStyle; save() },
                        onBuy: { if player.purchase(previewDotStyle) { save(); HapticsManager.shared.success() } }) {
                DotStylePreviewCanvas(style: previewDotStyle, diameter: 88)
            }
        }
    }

    @ViewBuilder
    private func previewCard<Preview: View>(
        name: String, owned: Bool, equipped: Bool, price: Int, plain: Bool = false,
        onEquip: @escaping () -> Void, onBuy: @escaping () -> Void, @ViewBuilder preview: () -> Preview
    ) -> some View {
        VStack(spacing: 12) {
            preview().padding(.vertical, 6)
            Text(name).font(.system(size: 18, weight: .bold, design: .rounded))

            if owned {
                if equipped {
                    Label("Equipped", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Button(action: onEquip) {
                        Text("Equip")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22).padding(.vertical, 10)
                    }
                    .background(Color.black, in: Capsule())
                    .buttonStyle(PressableButtonStyle())
                }
            } else {
                let canAfford = player.profile.points >= price
                Button(action: onBuy) {
                    HStack(spacing: 6) {
                        Image("Sparkle").renderingMode(.template).resizable().frame(width: 13, height: 13)
                        Text(canAfford ? "Buy for \(price)" : "Need \(price)")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                }
                .background(canAfford ? Color.black : Color.black.opacity(0.3), in: Capsule())
                .buttonStyle(PressableButtonStyle())
                .disabled(!canAfford)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        // Dot Styles pass `plain` (§ new — "for the custom dots don't use
        // border radius or shadows or background behind them"): the dot sits
        // straight on the sheet with no card, rounding or drop shadow around
        // it. Universes keep the card, since a Universe swatch *is* a
        // rounded tile and needs the surface to sit on.
        .background {
            if !plain {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            }
        }
    }

    // MARK: - Grids (tap = preview only, never commits)

    private var universeTiles: some View {
        ForEach(UniverseTheme.allCases) { theme in
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { previewUniverse = theme }
            } label: {
                VStack(spacing: 4) {
                    UniverseSwatch(theme: theme, isSelected: theme == previewUniverse, locked: !player.profile.owns(theme))
                    Text(theme.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var dotStyleTiles: some View {
        ForEach(DotStyle.allCases) { style in
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { previewDotStyle = style }
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        DotStylePreviewCanvas(style: style, diameter: 46)
                        if !player.profile.owns(style) {
                            Circle().fill(Color.black.opacity(0.35)).frame(width: 46, height: 46)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        if style == previewDotStyle {
                            Circle().stroke(Color.black.opacity(0.8), lineWidth: 2.5).frame(width: 50, height: 50)
                        }
                    }
                    .frame(height: 52)
                    Text(style.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
    }

}

/// The real paywall for Premium. Everything here goes through StoreKit:
/// the price comes from the product, the button opens Apple's purchase
/// sheet, and entitlement is read back from Apple afterwards. App Review
/// requires the auto-renew disclosure, a Restore Purchases control and
/// reachable Terms/Privacy links on any screen that sells a subscription
/// (Guideline 3.1.2), so all four live here.
private struct PremiumUnlockSheet: View {
    @ObservedObject var store: StoreManager
    @ObservedObject var player: PlayerState
    @ObservedObject var authState: AuthState
    var save: () -> Void
    @State private var showSignInGate = false
    var onPurchased: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.black.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Text("Premium")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("Unlocks every Universe look and every Dot Style — cosmetic only, never a gameplay advantage.")
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if player.profile.isPremium {
                Label("Premium is active.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.top, 8)
            } else if store.isLoadingProduct {
                ProgressView().padding(.top, 16)
            } else {
                Button(action: buy) {
                    Group {
                        if store.purchaseInFlight {
                            ProgressView().tint(.white)
                        } else {
                            Text(store.subscribeTitle)
                        }
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 260, height: 48)
                }
                .background(store.premiumProduct == nil ? Color.black.opacity(0.3) : Color.black)
                .clipShape(Capsule())
                .buttonStyle(PressableButtonStyle())
                .disabled(store.premiumProduct == nil || store.purchaseInFlight)
                .padding(.top, 8)

                // Required disclosure — price, period and auto-renewal, in
                // plain text right next to the buy button.
                Text(store.renewalDisclosure)
                    .font(.system(size: 11))
                    .foregroundColor(.black.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            if let message = store.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button(action: restore) {
                Text(store.restoreInFlight ? "Restoring…" : "Restore Purchases")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))
            }
            .disabled(store.restoreInFlight)

            HStack(spacing: 14) {
                Link("Terms of Use", destination: StoreManager.termsOfUseURL)
                Text("·").foregroundColor(.black.opacity(0.3))
                Link("Privacy Policy", destination: StoreManager.privacyPolicyURL)
            }
            .font(.system(size: 11))
            .foregroundColor(.black.opacity(0.45))

            Button("Not Now") { dismiss() }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.5))
                .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .presentationDetents([.fraction(0.72)])
        .task { await store.loadProduct() }
        .sheet(isPresented: $showSignInGate) { SignInRequiredSheet(authState: authState) }
    }

    private func buy() {
        // A purchase is tied to an account, not a device: without one there's
        // nothing to attach Premium to when the player reinstalls or picks up
        // another phone.
        guard !authState.isGuest else { showSignInGate = true; return }
        Task {
            let ok = await store.purchasePremium()
            player.refreshPremium(subscribed: store.isSubscribed)
            save()
            if ok {
                HapticsManager.shared.success()
                onPurchased()
            }
        }
    }

    private func restore() {
        Task {
            await store.restorePurchases()
            player.refreshPremium(subscribed: store.isSubscribed)
            save()
            if store.isSubscribed { HapticsManager.shared.success() }
        }
    }
}

/// The daily login reward (§ new) — a free 7-day Points ladder, opened from
/// the main menu's gift icon. Distinct from `StoreView`'s paid packs: nothing
/// here is ever purchased, so there's no "Test Mode" language needed — it's
/// just Points for showing up. One claim per calendar day
/// (`PlayerState.canClaimDailyReward`); missing a day resets the ladder back
/// to Day 1 without ever taking back Points already earned.
private struct DailyRewardSheet: View {
    @ObservedObject var player: PlayerState
    var save: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let gold = DotStyle.gold.swatchColor

    /// The ladder day to visually highlight/check off: the day about to be
    /// claimed if one is still available today, otherwise the day that was
    /// just claimed (so the sheet doesn't look like it forgot what happened
    /// the moment the claim button is tapped).
    private var displayIndex: Int {
        if player.canClaimDailyReward {
            return player.nextDailyRewardIndex
        }
        return (player.nextDailyRewardIndex - 1 + PlayerState.dailyRewardLadder.count)
            % PlayerState.dailyRewardLadder.count
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.black.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Text("Daily Reward")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("Come back every day to climb the ladder. Missing a day just resets it to Day 1 — you never lose Points you've already earned.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            HStack(spacing: 8) {
                ForEach(0..<PlayerState.dailyRewardLadder.count, id: \.self) { i in
                    ladderDay(i)
                }
            }
            .padding(.horizontal, 12)

            Button(action: claim) {
                Text(claimButtonTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 240, height: 48)
            }
            .background(player.canClaimDailyReward ? Color.black : Color.black.opacity(0.25))
            .clipShape(Capsule())
            .buttonStyle(PressableButtonStyle())
            .disabled(!player.canClaimDailyReward || player.pointsRemainingToday == 0)
            .padding(.top, 4)

            Button("Close") { dismiss() }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.5))
                .padding(.bottom, 12)

            Spacer()
        }
        .presentationDetents([.fraction(0.58)])
    }

    private func ladderDay(_ index: Int) -> some View {
        let isToday = index == displayIndex
        let isPast = index < displayIndex
        let isChecked = isPast || (isToday && !player.canClaimDailyReward)
        let dayColor = IconPalette.ladder[index % IconPalette.ladder.count]

        return VStack(spacing: 6) {
            Text("D\(index + 1)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
            ZStack {
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(dayColor)
                } else {
                    Image("Sparkle")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .foregroundColor(dayColor)
                }
            }
            .frame(width: 36, height: 36)
            .opacity(isToday ? 1.0 : (isPast ? 0.7 : 0.3))
            .scaleEffect(isToday ? 1.14 : 1.0)
            Text("\(PlayerState.dailyRewardLadder[index])")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.black.opacity(0.5))
        }
    }

    private var claimButtonTitle: String {
        guard player.canClaimDailyReward else { return "Come back tomorrow" }
        guard player.pointsRemainingToday > 0 else { return "Daily limit reached — claim tomorrow" }
        return "Claim +\(min(player.nextDailyRewardAmount, player.pointsRemainingToday)) Points"
    }

    private func claim() {
        let amount = player.claimDailyReward()
        guard amount > 0 else { return }
        // Save straight away: the claim also advanced the streak and stamped
        // today's date, so losing it to a crash would hand out the reward
        // twice.
        save()
        HapticsManager.shared.success()
    }
}

/// Shown when a guest taps anything that costs real money. A purchase is
/// tied to an Apple account, not to a device — without one there'd be
/// nothing to attach Premium to when the player reinstalls or moves to
/// another phone, and no way to restore it.
private struct SignInRequiredSheet: View {
    @ObservedObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var showPhraseSheet = false

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.black.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(IconPalette.blue)
                .padding(.top, 6)

            Text("Sign in to purchase")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text("Purchases are tied to your Apple Account, so they can be restored if you reinstall or switch devices. Playing stays free without an account.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                if authState.handleAppleSignIn(result) { dismiss() }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 260, height: 50)
            .clipShape(Capsule())
            .padding(.top, 4)

            Button { showPhraseSheet = true } label: {
                Text("Use a Spacechat phrase instead")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))
            }

            if let message = authState.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Button("Not Now") { dismiss() }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.5))
                .padding(.bottom, 14)

            Spacer(minLength: 0)
        }
        .presentationDetents([.fraction(0.62)])
        .sheet(isPresented: $showPhraseSheet) {
            SpacechatPhraseView(authState: authState) { dismiss() }
        }
    }
}

/// The Store — a full page (opened from the main menu's top-left bag icon),
/// not just a small confirmation sheet. Two ways to reach AI+ Premium here:
/// a real App Store subscription purchase of `spaces_vip` (see
/// `StoreManager`) or redeeming Points actually earned from play. Point
/// Packs remain local stand-ins until their consumable products exist in
/// App Store Connect.
private struct StoreView: View {
    @ObservedObject var player: PlayerState
    @ObservedObject var store: StoreManager
    @ObservedObject var authState: AuthState
    var save: () -> Void
    @State private var showSignInGate = false
    @Environment(\.dismiss) private var dismiss

    private let gold = DotStyle.gold.swatchColor

    /// Starter sets the base rate (~505 Points per dollar); Value and Mega
    /// pay that rate doubled and tripled (§ new — "add extra points to value
    /// and extra points to the mega... like 3x"). Before this, Value was
    /// actually *worse* value per dollar than Starter, so the middle tier had
    /// no reason to exist.
    /// `productID` must match App Store Connect exactly — including the
    /// Starter Pack's, which really is the string "0.99". `fallbackPrice` is
    /// only shown for the instant before StoreKit returns the real localized
    /// price; the live one always wins.
    private let pointPacks: [(name: String, productID: String, points: Int, multiplier: Int, fallbackPrice: String, icon: String, color: Color, highlight: Bool)] = [
        ("Starter Pack", "0.99", 500, 1, "$0.99", "shippingbox.fill", IconPalette.blue, false),
        ("Value Pack", "value", 3000, 2, "$2.99", "gift.fill", IconPalette.pink, false),
        ("Mega Pack", "mega", 12000, 3, "$7.99", "crown.fill", IconPalette.gold, true)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    balanceCard
                    membershipSection
                    universesSection
                    dotStylesSection
                    pointPacksSection
                    earnPointsSection

                    Text("Premium and Point Packs are real App Store purchases. Points are consumable and are not restored on a new device.")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.4))
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color(white: 0.96).ignoresSafeArea())
            .task {
                store.grantPoints = { points in
                    player.profile.points += points
                    save()
                }
                await store.loadProduct()
                await store.refreshEntitlement()
                player.refreshPremium(subscribed: store.isSubscribed)
            }
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSignInGate) { SignInRequiredSheet(authState: authState) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var balanceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Points")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black.opacity(0.55))
                HStack(spacing: 6) {
                    Image("Sparkle").renderingMode(.template).resizable()
                        .frame(width: 18, height: 18).foregroundColor(gold)
                    Text(formattedPoints)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            if player.profile.isPremium {
                Label("Premium Active", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.black, in: Capsule())
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: player.profile.points)
    }

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PREMIUM MEMBERSHIP")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.45))

            VStack(alignment: .leading, spacing: 12) {
                Text("Premium").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Unlocks every Universe look and every Dot Style — cosmetic only, never a gameplay advantage.")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))

                if player.profile.isPremium {
                    Label("You already have Premium.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Button(action: unlockPremium) {
                        HStack {
                            if store.purchaseInFlight {
                                ProgressView().tint(.white)
                            } else {
                                Text(store.subscribeTitle)
                            }
                            Spacer()
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(store.premiumProduct == nil ? Color.black.opacity(0.3) : Color.black,
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(store.premiumProduct == nil || store.purchaseInFlight)

                    // Guideline 3.1.2 disclosure, shown wherever the
                    // subscription can be bought.
                    Text(store.renewalDisclosure)
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.45))

                }

                if let message = store.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }

                HStack(spacing: 14) {
                    Button(store.restoreInFlight ? "Restoring…" : "Restore Purchases", action: restore)
                        .disabled(store.restoreInFlight)
                    Spacer()
                    Link("Terms", destination: StoreManager.termsOfUseURL)
                    Link("Privacy", destination: StoreManager.privacyPolicyURL)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.black.opacity(0.55))
                .padding(.top, 2)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }

    /// Every Universe, buyable one at a time with Points — a full shop
    /// listing to browse and buy from directly, alongside the home menu's
    /// own tap-a-locked-tile flow (§ new — "add more universes to buy").
    private var universesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UNIVERSES")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.45))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 16) {
                ForEach(UniverseTheme.allCases) { theme in
                    cosmeticCell(
                        name: theme.displayName,
                        price: theme.price,
                        owned: player.profile.owns(theme),
                        equipped: player.profile.selectedUniverse == theme,
                        preview: { UniverseSwatch(theme: theme, isSelected: true, locked: false) },
                        onEquip: { player.profile.selectedUniverse = theme; save() },
                        onBuy: { if player.purchase(theme) { save(); HapticsManager.shared.success() } }
                    )
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }

    /// Every Dot Style, same idea as `universesSection` above (§ new — "add
    /// more dots... set price for them").
    private var dotStylesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DOT STYLES")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.45))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 16) {
                ForEach(DotStyle.allCases) { style in
                    cosmeticCell(
                        name: style.displayName,
                        price: style.price,
                        owned: player.profile.owns(style),
                        equipped: player.profile.selectedDotStyle == style,
                        preview: { DotStylePreviewCanvas(style: style, diameter: 46).frame(height: 52) },
                        onEquip: { player.profile.selectedDotStyle = style; save() },
                        onBuy: { if player.purchase(style) { save(); HapticsManager.shared.success() } }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// One shop tile shared by both grids above — a small preview, its name,
    /// and either an "Equip"/"Equipped" state (already owned) or a
    /// "Buy N pts" button (still locked), so the same layout and behavior
    /// serves Universes and Dot Styles alike.
    @ViewBuilder
    private func cosmeticCell<Preview: View>(
        name: String, price: Int, owned: Bool, equipped: Bool,
        @ViewBuilder preview: () -> Preview, onEquip: @escaping () -> Void, onBuy: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            preview()
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.black.opacity(0.75))
                .lineLimit(1)

            if owned {
                if equipped {
                    Text("Equipped")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Button("Equip", action: onEquip)
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(PressableButtonStyle(scale: 0.94))
                }
            } else {
                let canAfford = player.profile.points >= price
                Button(action: onBuy) {
                    HStack(spacing: 3) {
                        Image("Sparkle").renderingMode(.template).resizable()
                            .frame(width: 9, height: 9)
                        Text("\(price)")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(canAfford ? .black : .black.opacity(0.3))
                .buttonStyle(PressableButtonStyle(scale: 0.94))
                .disabled(!canAfford)
            }
        }
    }

    private var pointPacksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("POINT PACKS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.45))

            VStack(spacing: 12) {
                ForEach(pointPacks, id: \.name) { pack in
                    Button(action: { buyPointPack(pack) }) {
                        HStack(spacing: 14) {
                            Image(systemName: pack.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(pack.color)
                                .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pack.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.black)
                                HStack(spacing: 4) {
                                    Image("Sparkle").renderingMode(.template).resizable()
                                        .frame(width: 11, height: 11).foregroundColor(gold)
                                    Text("+\(pack.points)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.black.opacity(0.7))
                                    if pack.multiplier > 1 {
                                        Text("· \(pack.multiplier)× value")
                                            .font(.system(size: 11))
                                            .foregroundColor(pack.color)
                                    }
                                }
                            }
                            Spacer()
                            Text(store.price(for: pack.productID) ?? pack.fallbackPrice)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color.black, in: Capsule())
                        }
                        .padding(14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                        .overlay(alignment: .topTrailing) {
                            if pack.multiplier > 1 {
                                Text(pack.highlight ? "BEST VALUE · \(pack.multiplier)× POINTS"
                                                    : "\(pack.multiplier)× POINTS")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(pack.highlight ? gold : pack.color, in: Capsule())
                                    .offset(x: -10, y: -8)
                            }
                        }
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                }
            }

            Text("Points are added to your profile as soon as the purchase completes.")
                .font(.system(size: 11))
                .foregroundColor(.black.opacity(0.4))
        }
    }

    private var earnPointsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EARN POINTS BY PLAYING")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.45))
            VStack(alignment: .leading, spacing: 12) {
                earnRow(icon: "sparkles", color: IconPalette.purple, text: "Eat collectibles — more Points for rarer finds")
                earnRow(icon: "checkmark.seal.fill", color: IconPalette.green, text: "Complete a form — +30 Points")
                earnRow(icon: "arrow.up.circle.fill", color: IconPalette.blue, text: "Level up — +15 Points")
                earnRow(icon: "clock.badge.checkmark.fill", color: IconPalette.orange,
                        text: player.pointsRemainingToday > 0
                            ? "\(player.pointsRemainingToday) of \(PlayerState.dailyEarnCap) Points left to earn today"
                            : "Daily earning limit reached — resets tomorrow")
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
    }

    private func earnRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 26, height: 26)
            Text(text).font(.system(size: 13)).foregroundColor(.black.opacity(0.7))
        }
    }

    private var formattedPoints: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: player.profile.points)) ?? "\(player.profile.points)"
    }

    // MARK: - Actions

    /// Real App Store purchase of `spaces_vip`. Nothing is granted locally —
    /// entitlement comes back from Apple and is folded in by
    /// `PlayerState.refreshPremium(subscribed:)`.
    private func unlockPremium() {
        guard !authState.isGuest else { showSignInGate = true; return }
        Task {
            let ok = await store.purchasePremium()
            player.refreshPremium(subscribed: store.isSubscribed)
            save()
            if ok { HapticsManager.shared.success() }
        }
    }

    private func restore() {
        Task {
            await store.restorePurchases()
            player.refreshPremium(subscribed: store.isSubscribed)
            save()
            if store.isSubscribed { HapticsManager.shared.success() }
        }
    }

    /// Real App Store purchase of a consumable. Points are credited by
    /// `StoreManager`'s redeem path (wired to `grantPoints` in `.task`), not
    /// here, so a transaction redelivered after a crash still pays out.
    private func buyPointPack(_ pack: (name: String, productID: String, points: Int, multiplier: Int, fallbackPrice: String, icon: String, color: Color, highlight: Bool)) {
        guard !authState.isGuest else { showSignInGate = true; return }
        Task {
            if await store.purchasePointPack(id: pack.productID) {
                HapticsManager.shared.impact(.light)
            }
        }
    }
}

/// A single, self-animating preview of the player dot — the same blue as
/// the app's own logo dot, drawn directly on the menu's white background
/// (no card/box around it), with plain white eyes (no pupil) to match the
/// logo's clean look. Uses the same squash-and-stretch body as the real
/// in-game player (`DotRenderer.drawPlayer`), just driven by a scripted
/// loop instead of real drag input — and reflects whichever Dot Style the
/// player currently has selected, so this preview is always accurate.
/// A few sparkle glyphs drifting slowly around the preview dot for premium
/// Dot Styles — reuses the same "Sparkle" template image the in-round
/// celebration bursts use (`SparkleBurst` in `WhiteSpaceView.swift`), just
/// looping continuously and gently instead of bursting-and-fading once.
/// Skipped under Reduce Motion, same as every other looping decoration.
private struct OrbitingSparkles: View {
    let color: Color
    var reduceMotion: Bool = false

    private let points: [(angle: Double, radius: CGFloat, size: CGFloat, speed: Double)] = [
        (30, 74, 11, 0.5), (155, 82, 8, 0.4), (265, 70, 12, 0.6)
    ]

    var body: some View {
        Group {
            if reduceMotion {
                EmptyView()
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(points.indices, id: \.self) { i in
                            let p = points[i]
                            let angle = p.angle * .pi / 180 + t * p.speed
                            let twinkle = 0.5 + 0.5 * sin(t * 2.4 + Double(i) * 1.3)
                            Image("Sparkle")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: p.size, height: p.size)
                                .foregroundColor(color)
                                .opacity(0.35 + 0.5 * twinkle)
                                .offset(x: cos(angle) * p.radius, y: sin(angle) * p.radius * 0.6)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A small friendly cluster for the main menu (§ new "AI motions" pass): the
/// player's own dot in the middle, kept genuinely round (no more looping
/// squash-into-a-teardrop) but with a constant tiny nervous shake layered on
/// top of `DotRenderer`'s built-in liquid wobble — reads as alive/idling
/// rather than "about to move" — plus two smaller companion dots flanking it.
/// All three now use `.withPupil` eyes (rather than the plain white ovals
/// used elsewhere) and glance toward wherever the player is currently
/// touching the cluster, falling back to a slow idle glance when they're not
/// — a drag anywhere in this view moves the touch point, no minimum distance
/// required, so it reads as instant eye contact rather than a swipe gesture.
/// The main menu's Dot Style switcher (§ new — replaces the old "Dot Style"
/// swatch row entirely): the player's own dot stays in the middle, in full
/// focus, with soft out-of-focus previews of the previous/next style
/// flanking it, exactly like a carousel's off-center cards. Tapping either
/// side jumps straight to that style (or opens the AI+ sheet if it's still
/// locked) via `onSelectStyle`/`onLockedTap`. Every eye everywhere here stays
/// the plain white-oval style — no black pupil — matching the app's own
/// clean logo dot; the touch point still nudges a gentle glance for a bit of
/// life while dragging, it just no longer needs a filled pupil to show it.
private struct PlayPreviewDot: View {
    var reduceMotion: Bool = false
    var dotStyle: DotStyle = .classic
    /// Shown on the centre dot only. The flanking dots stay as catalog
    /// styles — they're the browse targets, and tapping one equips it.
    var customDot: CustomDot? = nil
    var isUnlocked: (DotStyle) -> Bool = { _ in true }
    var onSelectStyle: (DotStyle) -> Void = { _ in }
    var onLockedTap: (DotStyle) -> Void = { _ in }

    private let blue = Color(red: 41 / 255, green: 121 / 255, blue: 255 / 255)
    // Taller than the cluster strictly needs at rest, with the center placed
    // low in that extra headroom rather than dead-center — the equipped
    // dot's worn hat (premium Dot Styles) rides well above its own body, and
    // between that, breathing bigger, and the new idle float below, the old
    // shorter frame was clipping it right at the top edge (§ user feedback:
    // "make sure the dots not being cut from the top").
    private let clusterSize = CGSize(width: 240, height: 210)
    private let sideOffset: CGFloat = 78
    private let verticalOffset: CGFloat = 30
    private let companionRadius: CGFloat = 20

    // Only a little below the frame's own center (not dead-center) so
    // `OrbitingSparkles`, which orbits around this view's frame center,
    // still reads as circling the dot rather than sitting oddly high above it.
    private var clusterCenter: CGPoint { CGPoint(x: clusterSize.width / 2, y: clusterSize.height / 2 + 15) }
    private var leftCenter: CGPoint { CGPoint(x: clusterCenter.x - sideOffset, y: clusterCenter.y + verticalOffset) }
    private var rightCenter: CGPoint { CGPoint(x: clusterCenter.x + sideOffset, y: clusterCenter.y + verticalOffset) }

    private var previousStyle: DotStyle {
        let all = Array(DotStyle.allCases)
        let i = all.firstIndex(of: dotStyle) ?? 0
        return all[(i - 1 + all.count) % all.count]
    }
    private var nextStyle: DotStyle {
        let all = Array(DotStyle.allCases)
        let i = all.firstIndex(of: dotStyle) ?? 0
        return all[(i + 1) % all.count]
    }

    @State private var touchPoint: CGPoint? = nil

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = clusterCenter

                func look(from dotCenter: CGPoint, idlePhase: Double, driftDX: Double = 0, driftDY: Double = 0) -> CGVector {
                    guard let touchPoint else {
                        // Nobody's touching it right now — the idle glance
                        // follows the dot's OWN drift direction (the analytic
                        // derivative of its float motion below) rather than a
                        // generic sine unrelated to how the body is actually
                        // moving, so the eyes read as physically attached to
                        // the dot instead of a layer riding on top of it
                        // (§ user feedback: "let the dot move as connect to
                        // the part of the dot so when dot move somewhere the
                        // eye will move with it"). A small residual bob is
                        // kept on top so the eyes still have a touch of life
                        // at the instants the drift itself passes through zero.
                        let bob = sin(t * 0.6 + idlePhase) * 0.2
                        return CGVector(dx: CGFloat(driftDX) * 0.7, dy: CGFloat(driftDY) * 0.7 + bob)
                    }
                    let maxDist: CGFloat = 70
                    let dx = (touchPoint.x - dotCenter.x) / maxDist
                    let dy = (touchPoint.y - dotCenter.y) / maxDist
                    return CGVector(dx: max(-1, min(1, dx)), dy: max(-1, min(1, dy)))
                }

                // A small constant tremor — high-frequency, low-amplitude,
                // and layered on top of (not instead of) the body's own slow
                // liquid wobble — is what actually reads as "alive and
                // paying attention" rather than the old approach of
                // periodically morphing into a stretched-out teardrop.
                let jitterX = reduceMotion ? 0 : CGFloat(sin(t * 9.0) * 0.55 + sin(t * 13.7 + 1.3) * 0.35)
                let jitterY = reduceMotion ? 0 : CGFloat(sin(t * 11.3 + 0.7) * 0.5 + sin(t * 7.1 + 2.1) * 0.35)
                // A slow, gentle float layered on top of that tremor — much
                // bigger and much slower, like it's quietly hovering rather
                // than pinned dead-still (§ user feedback: the movement and
                // animation should read as much better/livelier). Purely
                // vertical-and-slight-horizontal so it never drifts anywhere
                // near the companions to either side.
                let floatX = reduceMotion ? 0 : CGFloat(sin(t * 0.7 + 0.4) * 4)
                let floatY = reduceMotion ? 0 : CGFloat(sin(t * 0.85) * 7)
                // A gentle per-axis drift direction fed to the idle eye
                // glance below — the sign/shape of each axis's own velocity
                // (`cos` of the same phase `floatX`/`floatY` use, scaled
                // down), kept deliberately PER-AXIS rather than normalized
                // into a single unit vector. Normalizing (dividing by the
                // combined speed) was tried and reverted: whenever both axes
                // drift near zero at once the normalized direction has to
                // swing wildly to stay unit-length, which is exactly what
                // made the dot look like it was spazzing out. Per-axis
                // values just fade to zero smoothly instead, with no
                // division and nothing to blow up.
                let mainDriftDX = reduceMotion ? 0 : cos(t * 0.7 + 0.4)
                let mainDriftDY = reduceMotion ? 0 : cos(t * 0.85)
                let breathe = reduceMotion ? 1.0 : 1.0 + 0.05 * sin(t * 2.0)
                let mainCenter = CGPoint(x: center.x + jitterX + floatX, y: center.y + jitterY + floatY)

                // Back to the calm, proven squash/stretch — a smoothly
                // bounded sine for both amount and angle. (A version that
                // derived the angle from the instantaneous drift direction
                // via `atan2` was tried and reverted for the same reason as
                // above: that angle spins rapidly whenever the drift passes
                // near zero, which read as the dot's whole body twitching.)
                let stretch = reduceMotion ? 0 : CGFloat(0.06 + 0.06 * sin(t * 1.3))
                let angle = reduceMotion ? Angle(radians: 0) : Angle(radians: sin(t * 1.6) * 0.09)

                DotRenderer.drawPlayer(context, center: mainCenter, radius: 44 * breathe, color: blue,
                                        stretch: stretch, angle: angle,
                                        lookDirection: look(from: mainCenter, idlePhase: 0, driftDX: mainDriftDX, driftDY: mainDriftDY), time: t,
                                        eyeStyle: .whiteOnly, reduceMotion: reduceMotion,
                                        dotStyle: dotStyle, customDot: customDot)

                // Soft, out-of-focus previews of the previous/next Dot Style
                // — blurred and slightly dimmed, carousel-style, so the
                // center dot (the one actually equipped) stays the obvious
                // focal point. These stay free of the tremor/squash above
                // (§ user feedback: they shouldn't shake unless selected),
                // but now get their own slow, quiet float+breathe so the
                // whole cluster reads as alive instead of two frozen cutouts
                // flanking the one dot that moves — tap one (see the gesture
                // below) to make it the equipped one, and it's the one that
                // starts shaking.
                let leftBob = reduceMotion ? 0 : CGFloat(sin(t * 0.75 + 0.9) * 3)
                let leftBreathe = reduceMotion ? 1.0 : 1.0 + 0.03 * sin(t * 1.4 + 0.9)
                var leftContext = context
                leftContext.opacity = 0.7
                leftContext.addFilter(.blur(radius: 3))
                let leftDriftDY = reduceMotion ? 0 : Double(cos(t * 0.75 + 0.9))
                DotRenderer.drawPlayer(leftContext, center: CGPoint(x: leftCenter.x, y: leftCenter.y + leftBob),
                                        radius: companionRadius * leftBreathe, color: blue,
                                        stretch: 0, angle: .zero, lookDirection: look(from: leftCenter, idlePhase: 0.9, driftDY: leftDriftDY),
                                        time: t, eyeStyle: .whiteOnly, reduceMotion: reduceMotion, dotStyle: previousStyle)

                let rightBob = reduceMotion ? 0 : CGFloat(sin(t * 0.75 + 1.7) * 3)
                let rightBreathe = reduceMotion ? 1.0 : 1.0 + 0.03 * sin(t * 1.4 + 1.7)
                var rightContext = context
                rightContext.opacity = 0.7
                rightContext.addFilter(.blur(radius: 3))
                let rightDriftDY = reduceMotion ? 0 : Double(cos(t * 0.75 + 1.7))
                DotRenderer.drawPlayer(rightContext, center: CGPoint(x: rightCenter.x, y: rightCenter.y + rightBob),
                                        radius: companionRadius * rightBreathe, color: blue,
                                        stretch: 0, angle: .zero, lookDirection: look(from: rightCenter, idlePhase: 1.7, driftDY: rightDriftDY),
                                        time: t, eyeStyle: .whiteOnly, reduceMotion: reduceMotion, dotStyle: nextStyle)
            }
        }
        .frame(width: clusterSize.width, height: clusterSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in touchPoint = value.location }
                .onEnded { value in
                    defer { touchPoint = nil }
                    // Only a genuine tap (barely any movement) switches
                    // styles — a real drag just drives the glance above and
                    // shouldn't also accidentally flip the equipped style.
                    let travel = hypot(value.location.x - value.startLocation.x,
                                        value.location.y - value.startLocation.y)
                    guard travel < 12 else { return }
                    let hitRadius = companionRadius + 16
                    if hypot(value.location.x - leftCenter.x, value.location.y - leftCenter.y) < hitRadius {
                        select(previousStyle)
                    } else if hypot(value.location.x - rightCenter.x, value.location.y - rightCenter.y) < hitRadius {
                        select(nextStyle)
                    }
                }
        )
    }

    private func select(_ style: DotStyle) {
        if isUnlocked(style) {
            HapticsManager.shared.impact(.light)
            onSelectStyle(style)
        } else {
            onLockedTap(style)
        }
    }
}

/// The main menu's "change your name" sheet (§ new — reachable by tapping
/// the handle shown above the dot preview, right on the home page rather
/// than buried in Settings). Same minimal `NavigationStack` + `Form` style as
/// `SettingsView`, just the one field.
private struct RenameSheet: View {
    let currentName: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    /// Same shape the generated "davi_32" handles use — lowercase letters,
    /// digits, and underscores only — so a player-picked name still reads
    /// consistently next to every rival's name under the dots in the universe.
    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isValid: Bool {
        !trimmed.isEmpty && trimmed.count <= 16
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $draft)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: draft) { newValue in
                            // Keep it to the same simple handle shape as the
                            // generated names (letters/digits/underscore),
                            // filtered live rather than rejected after the fact.
                            let filtered = newValue.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            if filtered != newValue { draft = filtered }
                            if draft.count > 16 { draft = String(draft.prefix(16)) }
                        }
                } footer: {
                    Text("Shown under your dot in the universe, like other players' names.")
                }
            }
            .navigationTitle("Change Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .onAppear { draft = currentName }
    }
}
