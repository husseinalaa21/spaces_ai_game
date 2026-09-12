import SwiftUI

/// The main White Space screen: the huge world, the player's dot, collectibles,
/// movement, and the minimal HUD. Fills the entire phone screen edge-to-edge
/// (§41: "avoid huge bars, large opaque panels, clutter").
struct WhiteSpaceView: View {
    @ObservedObject var engine: GameEngine
    @ObservedObject var player: PlayerState
    @State private var dragStart: CGPoint? = nil
    @State private var lastTick: Date = Date()
    @State private var showingCollection = false
    @State private var showingSettings = false

    var body: some View {
        GeometryReader { geo in
            let screenSize = geo.size
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    draw(context: &context, size: size, screenSize: screenSize)
                }
                .onChange(of: timeline.date) { newDate in
                    let dt = newDate.timeIntervalSince(lastTick)
                    lastTick = newDate
                    engine.tick(dt: dt)
                }
            }
            .background(Color.white)
            .contentShape(Rectangle())
            .gesture(dragGesture(screenSize: screenSize))
            .overlay(alignment: .top) { hud }
            .overlay(alignment: .bottom) { controls }
            .overlay { formCompleteOverlay }
            .overlay(alignment: .top) { signalBanner }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingCollection) {
            CollectionView(player: player)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(player: player)
        }
    }

    // MARK: - Drawing

    private func draw(context: inout GraphicsContext, size: CGSize, screenSize: CGSize) {
        let camera = CGPoint(x: player.position.x - screenSize.width / 2,
                              y: player.position.y - screenSize.height / 2)

        func toScreen(_ world: CGPoint) -> CGPoint {
            CGPoint(x: world.x - camera.x, y: world.y - camera.y)
        }

        // Ambient wanderers (drawn faint/behind everything else).
        for w in engine.wanderers {
            let p = toScreen(w.position)
            guard isOnScreen(p, size: screenSize, margin: 40) else { continue }
            DotRenderer.draw(context, center: p, radius: w.radius, color: w.tint.color.opacity(0.55))
        }

        // Signal marker.
        if let signal = engine.activeSignal {
            let p = toScreen(signal.position)
            if isOnScreen(p, size: screenSize, margin: 80) {
                let pulse = CGFloat(1.0 + 0.15 * sin(Date().timeIntervalSinceReferenceDate * 3))
                let r: CGFloat = 30 * pulse
                context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                with: .color(.blue.opacity(0.6)), lineWidth: 2)
            }
        }

        // Collectibles.
        for c in engine.collectibles {
            let p = toScreen(c.position)
            guard isOnScreen(p, size: screenSize, margin: 40) else { continue }
            let radius: CGFloat = 13
            let isRare = c.definition.rarity >= .rare
            let wobble = Date().timeIntervalSinceReferenceDate * 4 + Double(p.x)
            let pulse: CGFloat = isRare ? CGFloat(1.0 + 0.08 * sin(wobble)) : 1.0
            let ringWidth = c.definition.rarity.ringLineWidth

            DotRenderer.draw(context, center: p, radius: radius * pulse,
                              color: c.definition.primaryColor.color.opacity(0.18),
                              ringColor: ringWidth > 0 ? c.definition.primaryColor.color : nil,
                              ringWidth: ringWidth)
            context.draw(Text(c.definition.icon).font(.system(size: 16)), at: p)
        }

        // Player dot, always screen-centered.
        let playerScreenPos = toScreen(player.position)
        let formColor = player.activeForm?.primaryColor.color
        let color = DotRenderer.blendedPlayerColor(formColor: formColor, progress: player.activeFormProgress)
        DotRenderer.draw(context, center: playerScreenPos, radius: player.size, color: color)

        if player.abilityEffectRemaining > 0 {
            let r = player.size + 6
            context.stroke(Path(ellipseIn: CGRect(x: playerScreenPos.x - r, y: playerScreenPos.y - r, width: r * 2, height: r * 2)),
                            with: .color((formColor ?? .blue).opacity(0.7)), lineWidth: 2)
        }

        if let bubble = player.chatBubble {
            context.draw(Text(bubble).font(.system(size: 13, weight: .medium)).foregroundColor(.black),
                         at: CGPoint(x: playerScreenPos.x, y: playerScreenPos.y - player.size - 18))
        }
    }

    private func isOnScreen(_ p: CGPoint, size: CGSize, margin: CGFloat) -> Bool {
        p.x > -margin && p.x < size.width + margin && p.y > -margin && p.y < size.height + margin
    }

    // MARK: - Movement input (drag anywhere, §42 Option A)

    private func dragGesture(screenSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                guard let start = dragStart else { return }
                let dx = value.location.x - start.x
                let dy = value.location.y - start.y
                let maxRange: CGFloat = 70
                let clampedX = max(-maxRange, min(maxRange, dx)) / maxRange
                let clampedY = max(-maxRange, min(maxRange, dy)) / maxRange
                engine.moveInput = CGVector(dx: clampedX, dy: clampedY)
            }
            .onEnded { _ in
                dragStart = nil
                engine.moveInput = .zero
            }
    }

    // MARK: - HUD

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if let form = player.activeForm {
                    Text("\(form.icon) \(form.name) \(Int(player.activeFormProgress))%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                } else {
                    Text("Explore.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Text("Intelligence \(player.profile.intelligenceLevel)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundColor(.black.opacity(0.75))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var controls: some View {
        HStack {
            VStack(spacing: 14) {
                roundIconButton(system: "square.grid.2x2.fill") { showingCollection = true }
                roundIconButton(system: "gearshape.fill") { showingSettings = true }
            }
            .padding(.leading, 20)
            .padding(.bottom, 28)

            Spacer()
            Button(action: { engine.triggerAbility() }) {
                ZStack {
                    Circle()
                        .fill(player.canUseAbility ? Color.black.opacity(0.85) : Color.gray.opacity(0.3))
                        .frame(width: 64, height: 64)
                    if player.abilityCooldownRemaining > 0 {
                        Text("\(Int(ceil(player.abilityCooldownRemaining)))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: abilityIconName)
                            .foregroundColor(.white)
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
            }
            .disabled(!player.canUseAbility)
            .padding(.trailing, 20)
            .padding(.bottom, 28)
        }
    }

    private func roundIconButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.black.opacity(0.75))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var abilityIconName: String {
        switch player.equippedAbility {
        case .slipperyDash, .rocketDash, .ghostPhase: return "bolt.fill"
        case .harden, .shieldUp: return "shield.fill"
        case .firePulse: return "flame.fill"
        case .slowPulse: return "snowflake"
        case .speedBoost, .flowEscape: return "wind"
        case .scan, .viewRange: return "eye.fill"
        case .magnetPull: return "circle.hexagongrid.fill"
        case .none: return "questionmark"
        }
    }

    private var formCompleteOverlay: some View {
        Group {
            if let form = player.formCompleteBanner {
                VStack(spacing: 6) {
                    Text(form.icon).font(.system(size: 40))
                    Text("\(form.name.uppercased()) — FORM COMPLETE")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .padding(20)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                .foregroundColor(.white)
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    HapticsManager.shared.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { player.formCompleteBanner = nil }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: player.formCompleteBanner)
    }

    private var signalBanner: some View {
        Group {
            if let text = engine.signalBannerText {
                Text(text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.black, in: Capsule())
                    .foregroundColor(.white)
                    .padding(.top, 50)
                    .transition(.opacity)
            }
        }
    }
}
