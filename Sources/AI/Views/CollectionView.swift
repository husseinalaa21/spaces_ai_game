import SwiftUI

/// The Collection screen (§48): every discovered/undiscovered form, grouped by
/// category, with progress, ability and rarity. Kept clean — no dense stat
/// tables during gameplay, per the "long descriptions belong in Collection"
/// guidance in §100.
struct CollectionView: View {
    @ObservedObject var player: PlayerState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: IconCategory? = nil

    private var categories: [IconCategory] { IconCategory.allCases }

    private var filtered: [CollectibleDefinition] {
        guard let selectedCategory else { return CollectibleCatalog.all }
        return CollectibleCatalog.all.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                categoryPicker
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { def in
                            CollectibleCard(definition: def,
                                             progress: player.progress(for: def.id),
                                             completed: player.isCompleted(def.id))
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summaryHeader: some View {
        HStack {
            statPill(title: "Forms", value: "\(player.profile.completedForms.count)/\(CollectibleCatalog.all.count)")
            statPill(title: "Intelligence", value: "\(player.profile.intelligenceLevel)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(title).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(categories) { cat in
                    chip(title: cat.displayName, isSelected: selectedCategory == cat) { selectedCategory = cat }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.black : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

private struct CollectibleCard: View {
    let definition: CollectibleDefinition
    let progress: Double
    let completed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(definition.icon).font(.system(size: 26))
                Spacer()
                Text(definition.rarity.rawValue.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(definition.primaryColor.color.opacity(0.18))
                    .foregroundColor(definition.primaryColor.color)
                    .clipShape(Capsule())
            }
            Text(definition.name).font(.system(size: 14, weight: .semibold))

            ProgressView(value: min(progress, 100), total: 100)
                .tint(definition.primaryColor.color)

            Text(completed ? "Completed" : "\(Int(progress))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(completed ? .green : .secondary)

            if let ability = definition.activeAbility {
                Text("Ability: \(ability.displayName)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
