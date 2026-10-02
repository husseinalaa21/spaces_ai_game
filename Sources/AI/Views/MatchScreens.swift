import SwiftUI

/// A glossy dot, drawn with the same renderer as the game.
struct OrbView: View {
    let color: Color
    var size: CGFloat = 44
    var body: some View {
        Canvas { ctx, s in
            DotRenderer.draw(ctx, center: CGPoint(x: s.width / 2, y: s.height / 2), radius: s.width / 2 - 2, color: color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Lobby

/// The wait before a match. It lasts as long as it really takes to gather the
/// players and their opening chat, with a floor so it never flashes past.
struct LobbyView: View {
    @ObservedObject var engine: GameEngine
    @ObservedObject var player: PlayerState
    let director: DotChatDirector
    let onReady: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var challenges = DailyChallenges.shared
    @State private var names: [String] = []
    @State private var joined = 0
    @State private var countdown: Int?
    @State private var elapsed = 0.0
    @State private var cancelled = false
    @State private var prepared = false
    private let total = GameEngine.rivalCount + 1

    var body: some View {
        ZStack {
            BlackBackdrop()
            VStack(spacing: 22) {
                Spacer().frame(height: 70)
                Text(countdown == nil ? "Finding players" : "Match starting")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(countdown == nil ? "Waiting for the match to fill" : "Get ready")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                ZStack {
                    if let countdown {
                        Text("\(countdown)")
                            .font(.system(size: 120, weight: .heavy, design: .rounded))
                            .foregroundColor(DotRenderer.defaultColor)
                            .id(countdown)
                            .transition(.scale.combined(with: .opacity))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 22) {
                        slot(name: player.profile.username ?? "you", color: DotRenderer.defaultColor, isYou: true)
                        ForEach(0..<GameEngine.rivalCount, id: \.self) { i in
                            if i < joined, i < names.count {
                                slot(name: names[i], color: GameEngine.rivalPalette[i % GameEngine.rivalPalette.count].color, isYou: false)
                                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                            } else {
                                Circle().fill(Color.white.opacity(0.07))
                                    .frame(width: 44, height: 44).frame(height: 66, alignment: .top)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .opacity(countdown == nil ? 1 : 0.15)
                }
                .frame(maxHeight: 260)

                Text("\(min(total, joined + 1)) of \(total) players")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundColor(.white.opacity(0.6))
                if !challenges.challenges.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Today's challenges", systemImage: "flag.checkered").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(DotRenderer.defaultColor)
                        ForEach(challenges.challenges) { c in ChallengeRow(challenge: c, challenges: challenges) }
                    }
                    .padding(14)
                    .background(PanelBackground())
                    .padding(.horizontal, 24).padding(.top, 6)
                }
                Spacer()
                Button(action: { cancelled = true; onCancel() }) {
                    Text("Leave")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 160, height: 46)
                        .background(PanelBackground())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 50)
            }
        }
        .foregroundColor(.white)
        .task { await run() }
    }

    private func slot(name: String, color: Color, isYou: Bool) -> some View {
        VStack(spacing: 5) {
            OrbView(color: color, size: 44)
            Text(isYou ? "You" : name)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(height: 66, alignment: .top)
    }

    private func run() async {
        let crew = NameGenerator.uniqueNames(count: GameEngine.rivalCount, excluding: Set([player.profile.username].compactMap { $0 }))
        names = crew
        engine.crewNames = crew
        let started = Date()

        // The real work: the players' opening conversation from the model.
        let preparing = Task { _ = await director.prepare(names: crew); prepared = true }
        let timeout = Task { try? await Task.sleep(nanoseconds: 13_000_000_000); preparing.cancel() }

        // Players trickle in while that happens.
        var nextJoin = 0.8
        while !Task.isCancelled && !cancelled {
            elapsed = Date().timeIntervalSince(started)
            if joined < GameEngine.rivalCount, elapsed >= nextJoin {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { joined += 1 }
                nextJoin = elapsed + Double.random(in: 0.7...1.5)
            }
            let ready = joined >= GameEngine.rivalCount && elapsed >= 5.5
            if ready, prepared { break }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        timeout.cancel()
        guard !cancelled, !Task.isCancelled else { return }
        for n in [3, 2, 1] {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { countdown = n }
            HapticsManager.shared.impact(.light)
            try? await Task.sleep(nanoseconds: 850_000_000)
            if cancelled { return }
        }
        onReady()
    }
}

// MARK: - Results

struct ResultsView: View {
    let result: GameResult
    @ObservedObject var friends: FriendsStore
    let onDone: () -> Void
    @ObservedObject private var challenges = DailyChallenges.shared
    @State private var recap: (text: String, tip: String)?

    var body: some View {
        ZStack {
            BlackBackdrop()
            VStack(spacing: 0) {
                Spacer().frame(height: 64)
                Text(result.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(.white.opacity(0.5))
                Text("\(result.score)")
                    .font(.system(size: 76, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundColor(DotRenderer.defaultColor)
                Text("score").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.45))
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 8) {
                        coachCard
                        if !challenges.challenges.isEmpty { challengeCard }
                        ForEach(Array(result.rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded)).frame(width: 24)
                                    .foregroundColor(.white.opacity(0.45))
                                OrbView(color: row.tint, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.isYou ? "You" : row.name)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                    Text(row.eaten ? "Eaten · \(row.mass) mass" : "\(row.mass) mass")
                                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.45))
                                }
                                Spacer()
                                if !row.isYou { friendButton(row.name) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(PanelBackground())
                        }
                    }.padding(.horizontal, 18)
                }
                Button(action: onDone) {
                    Text("Continue")
                        .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(DotRenderer.defaultColor, in: Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28).padding(.vertical, 22)
            }
        }
        .foregroundColor(.white)
    }

    /// The coach's words about the match (from the server, or the numbers).
    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Coach", systemImage: "sparkles").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(DotRenderer.defaultColor)
            if let recap {
                Text(recap.text).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.92))
                if !recap.tip.isEmpty {
                    Text("Tip: " + recap.tip).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(DotRenderer.defaultColor)
                }
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking at your match…").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.45)) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PanelBackground())
        .task { recap = await DotCoach.recap(result) }
    }

    private var challengeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's challenges", systemImage: "flag.checkered").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(DotRenderer.defaultColor)
            ForEach(challenges.challenges) { c in ChallengeRow(challenge: c, challenges: challenges, justCompleted: result.completed.contains(c)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PanelBackground())
    }

    private func friendButton(_ name: String) -> some View {
        let isFriend = friends.isFriend(name)
        return Button {
            if isFriend { friends.remove(name) } else { friends.add(name); HapticsManager.shared.impact(.light) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isFriend ? "checkmark" : "person.badge.plus").font(.system(size: 12, weight: .bold))
                Text(isFriend ? "Friends" : "Add friend").font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).frame(height: 34)
            .background(isFriend ? Color.white.opacity(0.12) : DotRenderer.defaultColor, in: Rectangle())
        }
        .buttonStyle(.plain)
    }
}


/// One daily challenge with its progress.
struct ChallengeRow: View {
    let challenge: Challenge
    @ObservedObject var challenges: DailyChallenges
    var justCompleted = false

    var body: some View {
        let done = challenges.isDone(challenge)
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .bold)).foregroundColor(done ? Color(red: 0.2, green: 0.75, blue: 0.4) : .black.opacity(0.25))
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.92))
                Text(done ? (justCompleted ? "Done! +\(challenge.reward) points" : "Done") : "\(challenges.value(for: challenge)) / \(challenge.target) · +\(challenge.reward) points")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.45))
            }
            Spacer()
        }
    }
}


/// Flat dark panel: no outline and no rounded corners.
struct PanelBackground: View {
    var body: some View { Rectangle().fill(Color.white.opacity(0.08)) }
}

/// Black with a slow drift of faint dots and a soft breathing glow: the look
/// of the waiting and results pages.
struct BlackBackdrop: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                // A glow that slowly breathes behind the middle of the screen.
                let breathe = 0.5 + 0.5 * sin(t * 0.6)
                let r = max(size.width, size.height) * (0.55 + 0.08 * breathe)
                let c = CGPoint(x: size.width / 2, y: size.height * 0.4)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [DotRenderer.defaultColor.opacity(0.16 + 0.06 * breathe), .clear]),
                                               center: c, startRadius: 0, endRadius: r))
                // Faint dots drifting upward, each at its own pace.
                for i in 0..<48 {
                    let seed = Double(i) * 12.9898
                    let x = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1) * size.width
                    let speed = 10 + abs(sin(seed * 1.7)) * 26
                    let span = Double(size.height) + 40
                    let y = size.height + 20 - CGFloat((t * speed + abs(sin(seed * 3.1)) * span).truncatingRemainder(dividingBy: span))
                    let radius = 1 + abs(sin(seed * 2.3)) * 2.2
                    let twinkle = 0.25 + 0.55 * abs(sin(t * 0.8 + seed))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(0.35 * twinkle)))
                }
            }
        }
        .ignoresSafeArea()
    }
}
