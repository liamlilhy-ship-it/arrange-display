import SwiftUI

/// Drag-to-arrange editor for a saved profile, in its own window.
/// Same visual language as the menu thumbnails: blue = main screen,
/// laptop = base bar, numbers in reading order, mirrors stacked behind.
///
/// Every feature is always available: profiles fit by screen count, so
/// mirroring is a structural role link and screens can be added or removed
/// freely. Hardware identity rides along invisibly for exact-monitor restore.
struct ProfileEditorView: View {
    @ObservedObject var store: ProfileStore
    let profileID: UUID?
    @Environment(\.dismiss) private var dismiss

    struct EditableDisplay: Identifiable {
        let id = UUID() // editor-local identity
        var hardwareUUID: String?
        var name: String?
        var size: CGSize
        let isBuiltin: Bool
        var origin: CGPoint
        var mirrorOfID: UUID? // nil = extended screen with a real position
    }

    @State private var displays: [EditableDisplay]
    @State private var profileName: String
    @State private var mainID: UUID?
    @State private var selectedID: UUID?
    @State private var dragAnchor: CGPoint?
    @State private var worldBounds: CGRect
    @State private var statusNote: String?
    @State private var connected: [DisplayInfo] = DisplayService.currentDisplays()

    private var profile: CustomProfile? {
        store.profiles.first { $0.id == profileID }
    }

    init(store: ProfileStore, profileID: UUID?) {
        self.store = store
        self.profileID = profileID
        let profile = store.profiles.first { $0.id == profileID }
        let loaded = Self.load(profile)
        _displays = State(initialValue: loaded)
        _profileName = State(initialValue: profile?.name ?? "")
        _mainID = State(initialValue: Self.initialMainID(of: loaded))
        _worldBounds = State(initialValue: Self.world(for: loaded))
    }

    // MARK: - State loading / geometry

    private static func load(_ profile: CustomProfile?) -> [EditableDisplay] {
        guard let profile else { return [] }
        var result: [EditableDisplay] = profile.displays.map {
            EditableDisplay(hardwareUUID: $0.uuid, name: $0.name,
                            size: CGSize(width: CGFloat($0.width), height: CGFloat($0.height)),
                            isBuiltin: $0.isBuiltin,
                            origin: CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)),
                            mirrorOfID: nil)
        }
        for i in profile.displays.indices {
            if let source = profile.displays[i].mirrorSourceIndex, result.indices.contains(source) {
                result[i].mirrorOfID = result[source].id
                result[i].origin = result[source].origin
            }
        }
        return result
    }

    private static func initialMainID(of displays: [EditableDisplay]) -> UUID? {
        (displays.first { $0.mirrorOfID == nil && $0.origin == .zero }
            ?? displays.first { $0.mirrorOfID == nil })?.id
    }

    /// World padded by the largest screen dimension so drags have room;
    /// fixed during a drag to avoid rescale jitter.
    private static func world(for displays: [EditableDisplay]) -> CGRect {
        let extended = displays.filter { $0.mirrorOfID == nil }
        let bounds = extended.map { CGRect(origin: $0.origin, size: $0.size) }
            .reduce(CGRect.null) { $0.union($1) }
        let slack = extended.map { max($0.size.width, $0.size.height) }.max() ?? 0
        return bounds.insetBy(dx: -slack, dy: -slack)
    }

    private var extendedDisplays: [EditableDisplay] { displays.filter { $0.mirrorOfID == nil } }
    private var selected: EditableDisplay? { displays.first { $0.id == selectedID } }

    // MARK: - Body

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
        .navigationTitle(profileName.isEmpty ? "Edit Arrangement" : "Edit “\(profileName)”")
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
                ForEach(mirrorCards(), id: \.display.id) { card in
                    mirrorCardView(card, scale: scale, offset: offset)
                }
                ForEach(extendedDisplays) { display in
                    displayView(display, number: numbers[display.id] ?? 0, scale: scale, offset: offset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { selectedID = nil }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { press in nudge(press) }
    }

    private struct MirrorCard {
        let display: EditableDisplay
        let source: EditableDisplay
        let ordinal: Int // 1st, 2nd… mirror of this source
    }

    private func mirrorCards() -> [MirrorCard] {
        var countPerSource: [UUID: Int] = [:]
        return displays.compactMap { d in
            guard let sourceID = d.mirrorOfID,
                  let source = displays.first(where: { $0.id == sourceID }) else { return nil }
            let ordinal = (countPerSource[sourceID] ?? 0) + 1
            countPerSource[sourceID] = ordinal
            return MirrorCard(display: d, source: source, ordinal: ordinal)
        }
    }

    private func mirrorCardView(_ card: MirrorCard, scale: CGFloat, offset: CGPoint) -> some View {
        let isSelected = card.display.id == selectedID
        let shift = CGFloat(card.ordinal) * 5
        return RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.25))
            .stroke(isSelected ? Color.primary : Color.secondary, lineWidth: isSelected ? 2.5 : 1)
            .frame(width: card.source.size.width * scale, height: card.source.size.height * scale)
            .position(x: (card.source.origin.x + card.source.size.width / 2) * scale + offset.x + shift,
                      y: (card.source.origin.y + card.source.size.height / 2) * scale + offset.y - shift)
            .onTapGesture { selectedID = card.display.id }
    }

    private func displayView(_ display: EditableDisplay, number: Int, scale: CGFloat, offset: CGPoint) -> some View {
        let isMain = display.id == mainID
        let isSelected = display.id == selectedID
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
                    selectedID = display.id
                    let anchor = dragAnchor ?? display.origin
                    dragAnchor = anchor
                    let raw = CGPoint(x: anchor.x + value.translation.width / scale,
                                      y: anchor.y + value.translation.height / scale)
                    move(display.id, to: snapped(raw, for: display, threshold: 8 / scale))
                }
                .onEnded { _ in
                    dragAnchor = nil
                    worldBounds = Self.world(for: displays)
                }
        )
        .onTapGesture { selectedID = display.id }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField("Profile name", text: $profileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Text(selectionInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("Add External") { addExternal() }
                Button("Remove Screen") { removeSelected() }
                    .disabled(!canRemoveSelected)
            }

            HStack(spacing: 8) {
                mirrorMenu

                Button("Set as Main") {
                    if let selectedID { mainID = selectedID }
                }
                .disabled(selected == nil || selected?.mirrorOfID != nil || selectedID == mainID)

                if let statusNote {
                    Text(statusNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Apply Now") { applyNow() }
                    .disabled(currentProfile().placements(matching: connected) == nil)
                Button("Reset") { reset() }
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private var selectionInfo: String {
        guard let selected else { return "Drag screens to arrange. Click one to select it." }
        let numbers = readingOrderNumbers()
        if let sourceID = selected.mirrorOfID {
            return "Mirrors Screen \(numbers[sourceID] ?? 0)\(selected.name.map { " — \($0)" } ?? "")"
        }
        let size = "\(Int(selected.size.width))×\(Int(selected.size.height))"
        return "Screen \(numbers[selected.id] ?? 0) — \(size)\(selected.name.map { " (\($0))" } ?? "")"
    }

    // MARK: - Mirroring

    private var mirrorMenu: some View {
        Menu("Mirror") {
            if let selected {
                if selected.mirrorOfID != nil {
                    Button("Stop Mirroring") { stopMirroring(selected.id) }
                } else if selected.id == mainID {
                    Text("The main screen can't mirror")
                } else {
                    let numbers = readingOrderNumbers()
                    ForEach(extendedDisplays.filter { $0.id != selected.id }) { target in
                        Button("Mirror onto Screen \(numbers[target.id] ?? 0)") {
                            mirror(selected.id, onto: target.id)
                        }
                    }
                }
            }
        }
        .fixedSize()
        .disabled(selected == nil || extendedDisplays.count < 2 && selected?.mirrorOfID == nil)
    }

    private func mirror(_ id: UUID, onto targetID: UUID) {
        guard let i = displays.firstIndex(where: { $0.id == id }) else { return }
        // No chains: mirroring onto a mirror resolves to its source.
        let root = displays.first { $0.id == targetID }?.mirrorOfID ?? targetID
        displays[i].mirrorOfID = root
        // Screens that mirrored the collapsing screen follow it to the new source.
        for j in displays.indices where displays[j].mirrorOfID == id {
            displays[j].mirrorOfID = root
        }
        worldBounds = Self.world(for: displays)
        statusNote = nil
    }

    private func stopMirroring(_ id: UUID) {
        guard let i = displays.firstIndex(where: { $0.id == id }),
              let source = displays.first(where: { $0.id == displays[i].mirrorOfID })
        else { return }
        displays[i].mirrorOfID = nil
        displays[i].origin = CGPoint(x: source.origin.x + source.size.width, y: source.origin.y)
        worldBounds = Self.world(for: displays)
    }

    // MARK: - Screen management

    private func addExternal() {
        let bounds = extendedDisplays.map { CGRect(origin: $0.origin, size: $0.size) }
            .reduce(CGRect.null) { $0.union($1) }
        displays.append(EditableDisplay(hardwareUUID: nil, name: nil,
                                        size: CGSize(width: 1920, height: 1080),
                                        isBuiltin: false,
                                        origin: CGPoint(x: bounds.maxX, y: bounds.minY),
                                        mirrorOfID: nil))
        selectedID = displays.last?.id
        worldBounds = Self.world(for: displays)
    }

    private var canRemoveSelected: Bool {
        guard let selected, selected.mirrorOfID == nil else { return false }
        return selected.id != mainID && extendedDisplays.count > 1
    }

    private func removeSelected() {
        guard canRemoveSelected, let selectedID else { return }
        displays.removeAll { $0.id == selectedID }
        self.selectedID = nil
        worldBounds = Self.world(for: displays)
    }

    // MARK: - Apply / Reset / Save

    /// The editor state as a profile (unsaved), used for Apply Now and Save.
    /// Extended screens come first, so a mirror's source index is simply the
    /// source's position in the extended list.
    private func currentProfile() -> CustomProfile {
        let main = displays.first { $0.id == mainID } ?? extendedDisplays.first
        let shift = main?.origin ?? .zero
        let extended = extendedDisplays
        var saved: [SavedDisplay] = extended.map { d in
            SavedDisplay(uuid: d.hardwareUUID,
                         x: Int32((d.origin.x - shift.x).rounded()),
                         y: Int32((d.origin.y - shift.y).rounded()),
                         width: Int32(d.size.width), height: Int32(d.size.height),
                         isBuiltin: d.isBuiltin,
                         name: d.name)
        }
        for d in displays where d.mirrorOfID != nil {
            guard let sourceIndex = extended.firstIndex(where: { $0.id == d.mirrorOfID })
            else { continue }
            saved.append(SavedDisplay(uuid: d.hardwareUUID,
                                      x: saved[sourceIndex].x, y: saved[sourceIndex].y,
                                      width: Int32(d.size.width), height: Int32(d.size.height),
                                      isBuiltin: d.isBuiltin,
                                      mirrorSourceIndex: sourceIndex,
                                      name: d.name))
        }
        return CustomProfile(id: profileID ?? UUID(), name: profileName, displays: saved)
    }

    private func applyNow() {
        guard let placements = currentProfile().placements(matching: connected) else { return }
        do {
            try DisplayService.apply(placements: placements)
            connected = DisplayService.currentDisplays()
            statusNote = "Applied"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    private func reset() {
        let loaded = Self.load(profile)
        displays = loaded
        profileName = profile?.name ?? ""
        mainID = Self.initialMainID(of: loaded)
        selectedID = nil
        statusNote = nil
        worldBounds = Self.world(for: loaded)
    }

    private func save() {
        guard let profile else { return }
        let name = profileName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, name != profile.name {
            store.rename(id: profile.id, to: name)
        }
        store.update(id: profile.id, displays: currentProfile().displays)
        statusNote = "Saved"
    }

    // MARK: - Movement helpers

    private func nudge(_ press: KeyPress) -> KeyPress.Result {
        guard let selected, selected.mirrorOfID == nil else { return .ignored }
        let step: CGFloat = press.modifiers.contains(.shift) ? 1 : 10
        let delta: CGPoint
        switch press.key {
        case .leftArrow: delta = CGPoint(x: -step, y: 0)
        case .rightArrow: delta = CGPoint(x: step, y: 0)
        case .upArrow: delta = CGPoint(x: 0, y: -step)
        case .downArrow: delta = CGPoint(x: 0, y: step)
        default: return .ignored
        }
        move(selected.id, to: CGPoint(x: selected.origin.x + delta.x,
                                      y: selected.origin.y + delta.y))
        return .handled
    }

    private func move(_ id: UUID, to origin: CGPoint) {
        guard let i = displays.firstIndex(where: { $0.id == id }) else { return }
        var clamped = origin
        let size = displays[i].size
        clamped.x = min(max(clamped.x, worldBounds.minX), worldBounds.maxX - size.width)
        clamped.y = min(max(clamped.y, worldBounds.minY), worldBounds.maxY - size.height)
        displays[i].origin = clamped
    }

    /// Magnetic edge snapping against every other extended display: edges
    /// align or butt together; centers align too.
    private func snapped(_ origin: CGPoint, for display: EditableDisplay, threshold: CGFloat) -> CGPoint {
        let others = extendedDisplays.filter { $0.id != display.id }
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

    private func readingOrderNumbers() -> [UUID: Int] {
        let sorted = extendedDisplays.sorted {
            $0.origin.y != $1.origin.y ? $0.origin.y < $1.origin.y : $0.origin.x < $1.origin.x
        }
        return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.id, $0 + 1) })
    }
}
