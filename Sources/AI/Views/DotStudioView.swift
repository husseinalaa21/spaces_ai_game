import SwiftUI

/// The Dot Studio — where a player designs their own dot instead of picking
/// one from the catalog (§ new — "add a option to create a dot and customize
/// it... let user draw/paint or icon to customize the dot and save it").
///
/// Everything is edited on a normalized circle: paint and stickers are stored
/// as fractions of the dot's radius (see `CustomDot`), so a design made here
/// renders identically on the 46pt picker swatch and on the full-size dot in
/// the game. The canvas below is exactly `DotRenderer`'s own drawing code, so
/// what's on screen while editing is what ships into the game — there is no
/// second, approximate preview to drift out of sync.
///
/// Nothing is written to the profile until Save is tapped; Cancel discards
/// the whole session's work, including anything undone past.
struct DotStudioView: View {
    @ObservedObject var player: PlayerState
    var save: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Tool: String, CaseIterable, Identifiable {
        case paint, stickers, base
        var id: String { rawValue }
        var label: String {
            switch self {
            case .paint: return "Paint"
            case .stickers: return "Stickers"
            case .base: return "Color"
            }
        }
        var icon: String {
            switch self {
            case .paint: return "paintbrush.pointed.fill"
            case .stickers: return "face.smiling.fill"
            case .base: return "circle.fill"
            }
        }
    }

    // Working copy. The profile is untouched until Save.
    @State private var draft = CustomDot()
    @State private var tool: Tool = .paint
    @State private var paintColor: Color = .white
    @State private var brush: Double = 0.16
    @State private var stickerScale: Double = 0.55
    @State private var selectedSticker: UUID?
    /// Snapshots for undo, oldest first. Bounded so a long session can't grow
    /// without limit.
    @State private var history: [CustomDot] = []
    @State private var liveStroke: DotStroke?
    @State private var showFullTray = false

    private static let historyLimit = 40
    private static let canvasSize: CGFloat = 260

    private let palette: [Color] = [
        .white, .black,
        Color(red: 0.16, green: 0.47, blue: 1.00), Color(red: 0.08, green: 0.70, blue: 0.74),
        Color(red: 0.13, green: 0.70, blue: 0.42), Color(red: 0.90, green: 0.68, blue: 0.11),
        Color(red: 0.97, green: 0.55, blue: 0.13), Color(red: 0.95, green: 0.35, blue: 0.60),
        Color(red: 0.58, green: 0.35, blue: 0.94), Color(red: 0.92, green: 0.26, blue: 0.24)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                    .padding(.top, 8)

                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.45))
                    .frame(height: 30)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                toolPicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch tool {
                        case .paint: paintControls
                        case .stickers: stickerControls
                        case .base: baseControls
                        }
                    }
                    .padding(20)
                }
                .background(Color(white: 0.97))
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Customize Dot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Start from whatever is already saved, so reopening edits the
            // existing design rather than silently starting over.
            draft = player.profile.customDot
        }
    }

    // MARK: - Canvas

    /// The dot itself, drawn by the real renderer. The drag gesture paints
    /// when the paint tool is active and drags the selected sticker
    /// otherwise, so one gesture serves both without a mode switch.
    private var canvas: some View {
        let size = Self.canvasSize
        let radius = size * 0.34

        return ZStack {
            Circle()
                .fill(Color(white: 0.96))
                .frame(width: size, height: size)

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                DotRenderer.drawPlayer(
                    context, center: center, radius: radius,
                    color: draft.baseColor.color,
                    stretch: 0, angle: .zero, lookDirection: .zero, time: 0,
                    eyeStyle: .whiteOnly, reduceMotion: true, eatPulse: 0,
                    dotStyle: .classic, customDot: previewDot
                )
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)

            // Marks which sticker the size slider and Delete act on.
            if tool == .stickers, let id = selectedSticker,
               let sticker = draft.stickers.first(where: { $0.id == id }) {
                Circle()
                    .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: CGFloat(sticker.scale) * radius * 1.5,
                           height: CGFloat(sticker.scale) * radius * 1.5)
                    .position(x: size / 2 + CGFloat(sticker.position.x) * radius,
                              y: size / 2 + CGFloat(sticker.position.y) * radius)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = normalize(value.location, size: size, radius: radius)
                    switch tool {
                    case .paint: extendStroke(to: point)
                    case .stickers: moveSelectedSticker(to: point)
                    case .base: break
                    }
                }
                .onEnded { _ in
                    if tool == .paint { commitStroke() }
                }
        )
    }

    /// What the canvas shows mid-gesture: the saved draft plus the stroke
    /// currently under the finger, which isn't committed yet.
    private var previewDot: CustomDot? {
        var dot = draft
        if let liveStroke { dot.strokes.append(liveStroke) }
        return dot.isBlank ? nil : dot
    }

    /// Screen point → coordinates normalized to the radius, clamped to the
    /// circle so paint can't be stored outside the dot it will be clipped to.
    private func normalize(_ location: CGPoint, size: CGFloat, radius: CGFloat) -> CGPoint {
        var x = (location.x - size / 2) / radius
        var y = (location.y - size / 2) / radius
        let distance = sqrt(x * x + y * y)
        // 0.98 keeps a hair inside the edge so round line caps don't get
        // sheared flat by the clip.
        if distance > 0.98 {
            x = x / distance * 0.98
            y = y / distance * 0.98
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Painting

    private func extendStroke(to point: CGPoint) {
        guard draft.strokes.count < CustomDot.maxStrokes else { return }
        if var stroke = liveStroke {
            guard stroke.points.count < CustomDot.maxPointsPerStroke else { return }
            // Drop points that barely moved: fewer, cleaner segments, and a
            // far smaller save file on a long scribble.
            if let last = stroke.points.last {
                let dx = point.x - last.x, dy = point.y - last.y
                guard (dx * dx + dy * dy) > 0.0009 else { return }
            }
            stroke.points.append(point)
            liveStroke = stroke
        } else {
            liveStroke = DotStroke(points: [point], color: PaintColor(paintColor), width: brush)
        }
    }

    private func commitStroke() {
        guard let stroke = liveStroke else { return }
        liveStroke = nil
        pushHistory()
        draft.strokes.append(stroke)
    }

    // MARK: - Stickers

    private func addSticker(_ symbol: String) {
        guard draft.stickers.count < CustomDot.maxStickers else { return }
        pushHistory()
        let sticker = DotSticker(symbol: symbol, position: .zero,
                                 scale: stickerScale, color: PaintColor(paintColor))
        draft.stickers.append(sticker)
        selectedSticker = sticker.id
        HapticsManager.shared.impact(.light)
    }

    private func moveSelectedSticker(to point: CGPoint) {
        guard let id = selectedSticker,
              let index = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
        draft.stickers[index].position = point
    }

    private func deleteSelectedSticker() {
        guard let id = selectedSticker,
              let index = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
        pushHistory()
        draft.stickers.remove(at: index)
        selectedSticker = nil
    }

    // MARK: - History

    private func pushHistory() {
        history.append(draft)
        if history.count > Self.historyLimit { history.removeFirst() }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        draft = previous
        // The selection may point at a sticker that no longer exists.
        if let id = selectedSticker, !draft.stickers.contains(where: { $0.id == id }) {
            selectedSticker = nil
        }
        HapticsManager.shared.impact(.light)
    }

    private func clearAll() {
        pushHistory()
        draft.strokes.removeAll()
        draft.stickers.removeAll()
        selectedSticker = nil
    }

    // MARK: - Saving

    private func commit() {
        player.profile.customDot = draft
        // A blank design must not be equipped: it would look exactly like the
        // default dot while silently overriding whichever style is selected.
        player.profile.usesCustomDot = !draft.isBlank
        save()
        HapticsManager.shared.success()
        dismiss()
    }

    // MARK: - Controls

    private var hint: String {
        switch tool {
        case .paint: return "Drag on the dot to paint. Paint stays inside the dot."
        case .stickers:
            return draft.stickers.isEmpty
                ? "Tap an icon to add it, then drag it on the dot to place it."
                : "Drag on the dot to move the selected icon."
        case .base: return "Pick the dot's base color."
        }
    }

    private var toolPicker: some View {
        HStack(spacing: 8) {
            ForEach(Tool.allCases) { option in
                Button {
                    tool = option
                    if option != .stickers { selectedSticker = nil }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: option.icon).font(.system(size: 15, weight: .semibold))
                        Text(option.label).font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(tool == option ? .white : .black.opacity(0.65))
                    .background(tool == option ? Color.black : Color.black.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96))
            }
        }
    }

    private var paintControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("BRUSH COLOR")
            colorRow(selection: $paintColor)

            sectionTitle("BRUSH SIZE")
            HStack(spacing: 12) {
                Circle().fill(paintColor)
                    .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                    .frame(width: max(6, brush * 60), height: max(6, brush * 60))
                    .frame(width: 34)
                Slider(value: $brush, in: 0.04...0.34)
            }

            editingRow
        }
    }

    private var stickerControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("ICON COLOR")
            colorRow(selection: $paintColor)

            HStack {
                sectionTitle("ICONS")
                Spacer()
                Text("\(draft.stickers.count)/\(CustomDot.maxStickers)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black.opacity(0.4))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], spacing: 10) {
                ForEach(showFullTray ? DotSticker.catalog : Array(DotSticker.catalog.prefix(12)), id: \.self) { symbol in
                    Button { addSticker(symbol) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 20))
                            .foregroundColor(.black.opacity(0.75))
                            .frame(width: 46, height: 46)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.92))
                    .disabled(draft.stickers.count >= CustomDot.maxStickers)
                    .opacity(draft.stickers.count >= CustomDot.maxStickers ? 0.35 : 1)
                }
            }

            if DotSticker.catalog.count > 12 {
                Button(showFullTray ? "Show fewer" : "Show all icons") {
                    withAnimation(.easeInOut(duration: 0.2)) { showFullTray.toggle() }
                }
                .font(.system(size: 13, weight: .medium))
            }

            if selectedSticker != nil {
                sectionTitle("SELECTED ICON")
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.5))
                    Slider(value: Binding(
                        get: { stickerScale },
                        set: { newValue in
                            stickerScale = newValue
                            if let id = selectedSticker,
                               let index = draft.stickers.firstIndex(where: { $0.id == id }) {
                                draft.stickers[index].scale = newValue
                            }
                        }
                    ), in: 0.2...1.1)
                    Button(role: .destructive, action: deleteSelectedSticker) {
                        Image(systemName: "trash.fill").font(.system(size: 14))
                    }
                }
            }

            editingRow
        }
    }

    private var baseControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("BASE COLOR")
            colorRow(selection: Binding(
                get: { draft.baseColor.color },
                set: { draft.baseColor = PaintColor($0) }
            ))
            editingRow
        }
    }

    private var editingRow: some View {
        HStack(spacing: 10) {
            Button(action: undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(history.isEmpty)

            Spacer()

            Button(role: .destructive, action: clearAll) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(draft.isBlank)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.top, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.black.opacity(0.45))
    }

    /// Swatches plus a system colour picker, so the palette is fast and any
    /// other colour is still reachable.
    private func colorRow(selection: Binding<Color>) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, swatch in
                Button { selection.wrappedValue = swatch } label: {
                    Circle()
                        .fill(swatch)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(
                                PaintColor(swatch) == PaintColor(selection.wrappedValue)
                                    ? Color.black : Color.black.opacity(0.12),
                                lineWidth: PaintColor(swatch) == PaintColor(selection.wrappedValue) ? 2.5 : 1
                            )
                        )
                }
                .buttonStyle(PressableButtonStyle(scale: 0.9))
            }
            ColorPicker("", selection: selection, supportsOpacity: false)
                .labelsHidden()
        }
    }
}
