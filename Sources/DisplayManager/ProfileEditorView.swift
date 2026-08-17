import SwiftUI

/// Drag-to-arrange editor for a saved profile, in its own window.
/// Same visual language as the menu thumbnails: blue = main screen,
/// laptop = base bar, numbers in reading order, mirrors stacked behind.
struct ProfileEditorView: View {
    @ObservedObject var store: ProfileStore
    let profileID: UUID?
    @Environment(\.dismiss) private var dismiss

    struct EditableDisplay: Identifiable {
        let uuid: String
        let size: CGSize
        let isBuiltin: Bool
        var origin: CGPoint
        var id: String { uuid }
    }

    @State private var displays: [EditableDisplay] // extended only
    @State private var mirrors: [SavedDisplay] // passed through on save
    @State private var mainUUID: String?
    @State private var selectedUUID: String?
    @State private var dragAnchor: CGPoint?
    @State private var worldBounds: CGRect

    private var profile: CustomProfile? {
        store.profiles.first { $0.id == profileID }
    }

    init(store: ProfileStore, profileID: UUID?) {
        self.store = store
        self.profileID = profileID
        let profile = store.profiles.first { $0.id == profileID }
        let displays = (profile?.displays ?? []).filter { $0.mirrorSourceUUID == nil }.map {
            EditableDisplay(uuid: $0.uuid,
                            size: CGSize(width: CGFloat($0.width), height: CGFloat($0.height)),
                            isBuiltin: $0.isBuiltin,
                            origin: CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)))
        }
        _displays = State(initialValue: displays)
        _mirrors = State(initialValue: (profile?.displays ?? []).filter { $0.mirrorSourceUUID != nil })
        _mainUUID = State(initialValue: displays.first { $0.origin == .zero }?.uuid ?? displays.first?.uuid)
        // Fixed world so the view doesn't rescale mid-drag: initial bounds
        // padded by the largest display dimension on every side.
        let bounds = displays.map { CGRect(origin: $0.origin, size: $0.size) }
            .reduce(CGRect.null) { $0.union($1) }
        let slack = displays.map { max($0.size.width, $0.size.height) }.max() ?? 0
        _worldBounds = State(initialValue: bounds.insetBy(dx: -slack, dy: -slack))
    }

    var body: some View {
        VStack(spacing: 0) {
            if displays.isEmpty {
                Text("Profile not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                canvas
                Divider()
                controls
            }
        }
        .navigationTitle(profile.map { "Edit “\($0.name)”" } ?? "Edit Arrangement")
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / worldBounds.width,
                            geo.size.height / worldBounds.height)
            let offset = CGPoint(
                x: (geo.size.width - worldBounds.width * scale) / 2 - worldBounds.minX * scale,
                y: (geo.size.height - worldBounds.height * scale) / 2 - worldBounds.minY * scale
            )
            let numbers = readingOrderNumbers()

            ZStack {
                // Mirror cards behind their sources.
                ForEach(mirrors, id: \.uuid) { mirror in
                    if let source = displays.first(where: { $0.uuid == mirror.mirrorSourceUUID }) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.25))
                            .stroke(Color.secondary, lineWidth: 1)
                            .frame(width: source.size.width * scale, height: source.size.height * scale)
                            .position(x: (source.origin.x + source.size.width / 2) * scale + offset.x + 4,
                                      y: (source.origin.y + source.size.height / 2) * scale + offset.y - 4)
                    }
                }
                ForEach(displays) { display in
                    displayView(display, number: numbers[display.uuid] ?? 0, scale: scale, offset: offset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { selectedUUID = nil }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func displayView(_ display: EditableDisplay, number: Int, scale: CGFloat, offset: CGPoint) -> some View {
        let isMain = display.uuid == mainUUID
        let isSelected = display.uuid == selectedUUID
        let w = display.size.width * scale
        let h = display.size.height * scale

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isMain ? Color.blue : Color.secondary.opacity(0.35))
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.primary : Color.secondary, lineWidth: isSelected ? 2.5 : 1)
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isMain ? .white : .primary)
            if display.isBuiltin {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isMain ? Color.blue : Color.secondary.opacity(0.6))
                    .frame(width: w + 8, height: 3)
                    .offset(y: h / 2 + 3)
            }
        }
        .frame(width: w, height: h)
        .position(x: (display.origin.x + display.size.width / 2) * scale + offset.x,
                  y: (display.origin.y + display.size.height / 2) * scale + offset.y)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    selectedUUID = display.uuid
                    let anchor = dragAnchor ?? display.origin
                    dragAnchor = anchor
                    let raw = CGPoint(x: anchor.x + value.translation.width / scale,
                                     y: anchor.y + value.translation.height / scale)
                    move(display.uuid, to: snapped(raw, for: display, threshold: 8 / scale))
                }
                .onEnded { _ in dragAnchor = nil }
        )
        .onTapGesture { selectedUUID = display.uuid }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            Text("Drag screens to arrange. Click one to select it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Set as Main") {
                if let selectedUUID { mainUUID = selectedUUID }
            }
            .disabled(selectedUUID == nil || selectedUUID == mainUUID)

            Button("Cancel") { dismiss() }

            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func save() {
        guard let profile, let main = displays.first(where: { $0.uuid == mainUUID }) else { return }
        var saved: [SavedDisplay] = displays.map { d in
            SavedDisplay(uuid: d.uuid,
                         x: Int32((d.origin.x - main.origin.x).rounded()),
                         y: Int32((d.origin.y - main.origin.y).rounded()),
                         width: Int32(d.size.width), height: Int32(d.size.height),
                         isBuiltin: d.isBuiltin,
                         mirrorSourceUUID: nil)
        }
        saved += mirrors.map { m in
            let source = saved.first { $0.uuid == m.mirrorSourceUUID }
            return SavedDisplay(uuid: m.uuid,
                                x: source?.x ?? m.x, y: source?.y ?? m.y,
                                width: m.width, height: m.height,
                                isBuiltin: m.isBuiltin,
                                mirrorSourceUUID: m.mirrorSourceUUID)
        }
        store.update(id: profile.id, displays: saved)
        dismiss()
    }

    // MARK: - Geometry helpers

    private func move(_ uuid: String, to origin: CGPoint) {
        guard let i = displays.firstIndex(where: { $0.uuid == uuid }) else { return }
        var clamped = origin
        let size = displays[i].size
        clamped.x = min(max(clamped.x, worldBounds.minX), worldBounds.maxX - size.width)
        clamped.y = min(max(clamped.y, worldBounds.minY), worldBounds.maxY - size.height)
        displays[i].origin = clamped
    }

    /// Magnetic edge snapping against every other display: edges align or
    /// butt together; centers align too.
    private func snapped(_ origin: CGPoint, for display: EditableDisplay, threshold: CGFloat) -> CGPoint {
        let others = displays.filter { $0.uuid != display.uuid }
            .map { CGRect(origin: $0.origin, size: $0.size) }
        var result = origin
        var bestDX = threshold
        var bestDY = threshold
        for o in others {
            let xCandidates = [o.minX, o.maxX, o.minX - display.size.width,
                               o.maxX - display.size.width, o.midX - display.size.width / 2]
            for c in xCandidates where abs(c - origin.x) < bestDX {
                bestDX = abs(c - origin.x)
                result.x = c
            }
            let yCandidates = [o.minY, o.maxY, o.minY - display.size.height,
                               o.maxY - display.size.height, o.midY - display.size.height / 2]
            for c in yCandidates where abs(c - origin.y) < bestDY {
                bestDY = abs(c - origin.y)
                result.y = c
            }
        }
        return result
    }

    private func readingOrderNumbers() -> [String: Int] {
        let sorted = displays.sorted {
            $0.origin.y != $1.origin.y ? $0.origin.y < $1.origin.y : $0.origin.x < $1.origin.x
        }
        return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.uuid, $0 + 1) })
    }
}
