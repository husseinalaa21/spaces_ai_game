import SwiftUI

/// Make a dot or change one: its look (the same shapes, colours and moving eyes as the Spacechat AI page), its name and job,
/// a bio that tells the dot who it is, and instructions for how it works.
/// Built-in dots can change their look, bio and instructions, but keep their name and job.
struct DotEditorView: View {
    @ObservedObject var store: AgentsStore
    /// nil: a new dot.
    let agent: SpacesAgent?
    let onDone: () -> Void

    @State private var name = ""
    @State private var role = ""
    @State private var bio = ""
    @State private var instructions = ""
    @State private var hue = 0.5
    @State private var shape: String? = nil
    @State private var newID = "agent-" + UUID().uuidString
    @State private var access = AgentAccess()
    @State private var confirmDelete = false
    @ObservedObject private var shop = StoreManager.shared
    @State private var buying: BuyTarget?

    /// Colour, bio, instructions and new dots come with Customize.
    private var locked: Bool { !shop.has(StoreGoods.customizeID) }

    private var isNew: Bool { agent == nil }
    private var isBuiltIn: Bool { agent?.builtIn == true }
    private var dotID: String { agent?.visualKey ?? newID }

    private let presets: [(String, String, String)] = [
        ("Researcher", "Finds and explains things", "You look things up in the files you are given, explain them simply and say when you are unsure."),
        ("Designer", "Plans how things look", "You suggest clear, simple layouts, colours and wording, and edit design files when asked."),
        ("Tester", "Tries things and reports problems", "You check work carefully, list what is wrong and what to fix first."),
        ("Planner", "Turns ideas into steps", "You turn goals into short ordered steps and hand each step to the right teammate.")
    ]
    private let swatches: [Double] = [0.60, 0.36, 0.08, 0.84, 0.98, 0.14, 0.50, 0.74]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Group {
                            if let agent, agent.logo != nil { AgentAvatar(agent: agent, size: 124) }
                            else { SpacechatDotFace(key: dotID, size: 124, animated: true, hue: hue * 360, shape: shape ?? defaultShape) }
                        }
                        .frame(maxWidth: .infinity)
                        Text(name.isEmpty ? (agent?.name ?? "Your dot") : name).font(.system(size: 18, weight: .heavy, design: .rounded))
                        if !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(bio).font(.system(size: 12.5)).foregroundColor(.secondary).multilineTextAlignment(.center).lineLimit(3)
                        }
                    }
                    .padding(.vertical, 8).listRowBackground(Color.clear)
                }

                if locked {
                    Section {
                        Button { buying = BuyTarget(id: StoreGoods.customizeID, title: "Customize Dots", blurb: "Change any dot's colour, bio and instructions, and make your own dots.") } label: {
                            HStack {
                                Image(systemName: "lock.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unlock Customize").font(.subheadline.weight(.bold))
                                    Text("Colour, bio and instructions are part of Customize.").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(shop.price(for: StoreGoods.customizeID) ?? "Buy").font(.subheadline.weight(.bold))
                            }
                        }
                    }
                }

                if agent?.logo == nil {
                Section("Shape") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            shapeTile(nil, label: "Auto")
                            ForEach(SpacechatDotGeometry.shapeNames, id: \.self) { shapeTile($0, label: $0.capitalized) }
                        }.padding(.vertical, 8).padding(.horizontal, 10)
                    }
                }

                Section("Colour") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(swatches, id: \.self) { value in
                                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hue = value } } label: {
                                    Circle().fill(Color(hue: value, saturation: 0.7, brightness: 0.95)).frame(width: 34, height: 34)
                                        .overlay(Circle().stroke(abs(hue - value) < 0.005 ? Color.primary : .clear, lineWidth: 3).padding(-3))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.vertical, 6).padding(.horizontal, 3)
                    }
                    Slider(value: $hue, in: 0...1).tint(Color(hue: hue, saturation: 0.7, brightness: 0.95))
                }
                .disabled(locked).opacity(locked ? 0.45 : 1)
                }

                if !isBuiltIn {
                    Section("Name") { TextField("Name, like Ava", text: $name).textInputAutocapitalization(.words) }.disabled(locked).opacity(locked ? 0.45 : 1)
                    Section("What it does") { TextField("A short job, like \"checks my spelling\"", text: $role) }.disabled(locked).opacity(locked ? 0.45 : 1)
                }

                Section {
                    TextField("Who is this dot? Its personality, background, how it talks…", text: $bio, axis: .vertical).lineLimit(3...8)
                } header: { Text("Bio") } footer: { Text("Shown under the dot, and told to the dot so it stays in character.") }
                .disabled(locked).opacity(locked ? 0.45 : 1)

                Section {
                    TextField(isBuiltIn ? "Extra instructions (optional)" : "How it should work (optional)", text: $instructions, axis: .vertical).lineLimit(2...8)
                } header: { Text(isBuiltIn ? "Extra instructions" : "Instructions") }
                .disabled(locked).opacity(locked ? 0.45 : 1)

                if isNew {
                    Section("Start from") {
                        ForEach(presets, id: \.0) { preset in
                            Button { name = preset.0; role = preset.1; instructions = preset.2 } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.0).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                    Text(preset.1).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                if !isBuiltIn { Section("What it may do") { AccessToggles(access: $access) } }

                if let agent, !agent.builtIn {
                    Section { Button("Delete this dot", role: .destructive) { confirmDelete = true } }
                }
                if isBuiltIn {
                    Section { Button("Reset to the original look and bio", role: .destructive) { store.setTweak(AgentTweak(), for: agent!.id); onDone() } }
                }
            }
            .navigationTitle(isNew ? "New dot" : "Customize dot").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save", action: save).fontWeight(.bold)
                        .disabled((!isBuiltIn && name.trimmingCharacters(in: .whitespaces).isEmpty) || (isNew && locked))
                }
            }
            .confirmationDialog("Delete this dot?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let agent { store.delete(agent) }; onDone() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: load)
            .sheet(item: $buying) { QuickBuySheet(target: $0) }
        }
        .tint(.primary)
    }

    /// The shape a built-in dot has when none is picked.
    private var defaultShape: String? {
        switch dotID {
        case "builtin-dots": return "circle"
        case "builtin-coder": return "hexagon"
        case "builtin-writer": return "flower"
        case "builtin-reviewer": return "squircle"
        default: return nil
        }
    }

    private func shapeTile(_ value: String?, label: String) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { shape = value } } label: {
            VStack(spacing: 4) {
                SpacechatDotFace(key: dotID, size: 52, animated: false, hue: hue * 360, shape: value ?? defaultShape)
                    .overlay(Circle().stroke(shape == value ? Color.primary : .clear, lineWidth: 3).padding(-5))
                Text(label).font(.system(size: 10.5, weight: .semibold)).foregroundColor(.secondary)
            }
        }.buttonStyle(.plain)
    }

    private func load() {
        guard let agent else { return }
        name = agent.name; role = agent.role; hue = agent.hue; shape = agent.shape; bio = agent.bio; access = agent.access
        if agent.builtIn {
            instructions = store.tweaks[agent.id]?.extra ?? ""
        } else {
            instructions = agent.instructions
        }
    }

    private func save() {
        if let agent {
            if agent.builtIn {
                store.setTweak(AgentTweak(hue: hue, shape: shape, bio: bio.trimmingCharacters(in: .whitespacesAndNewlines), extra: instructions), for: agent.id)
            } else {
                var next = agent
                next.name = name; next.role = role.isEmpty ? "Helps with tasks" : role; next.instructions = instructions
                next.hue = hue; next.shape = shape; next.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines); next.access = access
                store.update(next)
            }
        } else {
            _ = store.add(id: newID, name: name, role: role.isEmpty ? "Helps with tasks" : role, instructions: instructions, hue: hue, access: access,
                          bio: bio.trimmingCharacters(in: .whitespacesAndNewlines), shape: shape)
        }
        onDone()
    }
}


/// Something the person tapped that is sold in the Store.
struct BuyTarget: Identifiable {
    let id: String
    let title: String
    let blurb: String
}

/// A small purchase sheet for one item, opened from a locked look in the editor or the workspace sheet.
struct QuickBuySheet: View {
    let target: BuyTarget
    @ObservedObject private var shop = StoreManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text(target.title).font(.system(size: 20, weight: .heavy, design: .rounded))
            Text(target.blurb).font(.system(size: 14)).foregroundColor(.secondary).multilineTextAlignment(.center)
            if shop.requiresSignIn() {
                Text("Sign in to buy this. Purchases belong to your account.").font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
            } else {
                Button {
                    Task { if await shop.purchase(goods: target.id) { HapticsManager.shared.success(); dismiss() } }
                } label: {
                    Group { if shop.purchaseInFlight { ProgressView().tint(.white) } else { Text("Buy \(shop.price(for: target.id) ?? "")") } }
                        .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(shop.goods[target.id] == nil ? Color.black.opacity(0.3) : Color.black, in: Capsule())
                }
                .disabled(shop.goods[target.id] == nil || shop.purchaseInFlight)
            }
            if let message = shop.errorMessage { Text(message).font(.system(size: 12)).foregroundColor(.red.opacity(0.8)) }
            Button("Not now") { dismiss() }.font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary)
        }
        .padding(24)
        .presentationDetents([.height(280)])
        .task { await shop.loadProduct() }
    }
}


/// A small padlock on a members-only dot for people who are not members.
struct MemberLockBadge: View {
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: "lock.fill").font(.system(size: size * 0.5, weight: .bold)).foregroundColor(.white)
            .frame(width: size, height: size).background(Color.black, in: Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
    }
}

/// Shown when someone taps Claude, ChatGPT or Grok without being a member: what membership is, with the same purchase, restore and legal rules as the Store.
struct MembersOnlySheet: View {
    @ObservedObject private var shop = StoreManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: -14) {
                    ForEach(["LogoClaude", "LogoChatGPT", "LogoGrok"], id: \.self) { name in
                        Image(name).resizable().scaledToFill().frame(width: 62, height: 62).clipShape(Circle()).overlay(Circle().stroke(Color.white, lineWidth: 3))
                    }
                }
                .padding(.top, 8)
                Text("Members only").font(.system(size: 22, weight: .heavy, design: .rounded))
                Text("Claude, ChatGPT and Grok dots are for members. Subscribe to add them to your team and talk to them.")
                    .font(.system(size: 14)).foregroundColor(.secondary).multilineTextAlignment(.center)
                if shop.isMember {
                    Label("You're a member", systemImage: "checkmark.seal.fill").font(.system(size: 15, weight: .bold)).foregroundColor(.green)
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .bold))
                } else {
                    if shop.premiumProduct != nil { SubscriptionSummaryView(store: shop) }
                    if shop.requiresSignIn() {
                        Text("Sign in with Spacechat first, then subscribe. Purchases belong to your account.").font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                    } else {
                        Button {
                            Task { if await shop.purchasePremium() { HapticsManager.shared.success(); dismiss() } }
                        } label: {
                            Group { if shop.purchaseInFlight { ProgressView().tint(.white) } else { Text(shop.subscribeTitle) } }
                                .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(shop.premiumProduct == nil ? Color.black.opacity(0.3) : Color.black, in: Capsule())
                        }
                        .disabled(shop.premiumProduct == nil || shop.purchaseInFlight)
                    }
                    Text(shop.renewalDisclosure).font(.system(size: 11.5)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let message = shop.errorMessage { Text(message).font(.system(size: 12)).foregroundColor(.red.opacity(0.8)) }
                    Button(shop.restoreInFlight ? "Restoring…" : "Restore Purchases") { Task { await shop.restorePurchases() } }
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary).disabled(shop.restoreInFlight)
                    SubscriptionLegalLinks()
                    Button("Not now") { dismiss() }.font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
        .task { await shop.loadProduct(); await shop.refreshEntitlement() }
    }
}
