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
                        SpacechatDotFace(key: dotID, size: 124, animated: true, hue: hue * 360, shape: shape ?? defaultShape)
                            .frame(maxWidth: .infinity)
                        Text(name.isEmpty ? (agent?.name ?? "Your dot") : name).font(.system(size: 18, weight: .heavy, design: .rounded))
                        if !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(bio).font(.system(size: 12.5)).foregroundColor(.secondary).multilineTextAlignment(.center).lineLimit(3)
                        }
                    }
                    .padding(.vertical, 8).listRowBackground(Color.clear)
                }

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

                if !isBuiltIn {
                    Section("Name") { TextField("Name, like Ava", text: $name).textInputAutocapitalization(.words) }
                    Section("What it does") { TextField("A short job, like \"checks my spelling\"", text: $role) }
                }

                Section {
                    TextField("Who is this dot? Its personality, background, how it talks…", text: $bio, axis: .vertical).lineLimit(3...8)
                } header: { Text("Bio") } footer: { Text("Shown under the dot, and told to the dot so it stays in character.") }

                Section {
                    TextField(isBuiltIn ? "Extra instructions (optional)" : "How it should work (optional)", text: $instructions, axis: .vertical).lineLimit(2...8)
                } header: { Text(isBuiltIn ? "Extra instructions" : "Instructions") }

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
                        .disabled(!isBuiltIn && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this dot?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let agent { store.delete(agent) }; onDone() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: load)
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
