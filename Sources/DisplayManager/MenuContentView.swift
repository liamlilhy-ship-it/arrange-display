import SwiftUI

/// A bordered, wrapping text field that grows in height with its content.
/// AppKit-backed: SwiftUI's TextField/TextEditor won't reliably auto-grow
/// inside the MenuBarExtra panel, so the height is measured from the cell.
struct GrowingTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
        let height = nsView.cell?.cellSize(forBounds: bounds).height ?? 22
        return CGSize(width: width, height: max(height, 20))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: GrowingTextField
        init(_ parent: GrowingTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }
    }
}

/// Shared naming UI for both "Save Current as Profile" and "Rename":
/// preview thumbnail, growing bordered input, character counter, ✓/✕.
struct ProfileNameEditor: View {
    let thumb: ArrangementThumbView
    @Binding var text: String
    let limit: Int
    let onCommit: () -> Void
    let onCancel: () -> Void

    private var trimmedEmpty: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            thumb.frame(width: 72, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                GrowingTextField(text: $text, onCommit: { if !trimmedEmpty { onCommit() } })
                    .padding(.vertical, 5)
                    .padding(.horizontal, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                    .onChange(of: text) { _, new in
                        if new.count > limit { text = String(new.prefix(limit)) }
                    }

                HStack(spacing: 10) {
                    Text("\(text.count)/\(limit)")
                        .font(.caption2)
                        .foregroundStyle(text.count >= limit ? .red : .secondary)
                    Spacer()
                    Button(action: onCommit) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedEmpty)
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

struct MenuContentView: View {
    @ObservedObject var service: DisplayService
    @ObservedObject var store: ProfileStore
    @Environment(\.openWindow) private var openWindow
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    // Inline "save current as profile" naming state.
    @State private var isNamingNewProfile = false
    @State private var newProfileName = ""

    // Inline rename state for custom profiles.
    @State private var renameTargetID: UUID?
    @State private var renameText = ""

    // Reorder mode: entered from a row's ... menu; rows show drag handles.
    // The dragged row floats with the finger; neighbors shift; the array
    // reorders once, on release — live array moves mid-drag cause jitter.
    @State private var isReordering = false
    @State private var dragState: (id: UUID, startIndex: Int, translation: CGFloat)?
    @State private var orderBackup: [UUID] = []

    private static let nameLimit = 50
    /// Fixed reorder-row height (54) plus the VStack spacing (8).
    private static let reorderRowStep: CGFloat = 62

    private var externalCount: Int { service.displays.filter { !$0.isBuiltin }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profiles")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                    profileRow(profile, index: index)
                }
            }
            .overlay(alignment: .top) { dragGhost }

            if isReordering {
                HStack {
                    Text("Drag the handles to reorder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { store.setOrder(orderBackup) }
                    Button("Done") { isReordering = false }
                }
                .padding(.horizontal, 12)
            } else {
                saveCurrentSection
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            Divider()

            HStack {
                Button("Edit Profiles…") {
                    openWindow(id: "profiles")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Spacer()

                Text("\(externalCount) external\(externalCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 300)
        .overlay(alignment: .bottom) { toastOverlay }
    }

    // MARK: - Rows

    @ViewBuilder
    private func profileRow(_ profile: CustomProfile, index: Int) -> some View {
        if isReordering {
            reorderRow(profile, index: index)
        } else if renameTargetID == profile.id {
            ProfileNameEditor(
                thumb: ArrangementThumbView(profile: profile),
                text: $renameText,
                limit: Self.nameLimit,
                onCommit: { commitRename(profile) },
                onCancel: { renameTargetID = nil }
            )
            .padding(.vertical, 4)
        } else {
            let applicable = profile.placements(matching: service.displays) != nil
            profileButton(
                title: profile.name,
                subtitle: subtitle(for: profile),
                enabled: applicable,
                thumb: ArrangementThumbView(profile: profile)
            ) {
                guard !isReordering else { return }
                attempt {
                    try service.apply(profile: profile)
                    showToast("Applied “\(profile.name)”")
                }
            }
            .overlay(alignment: .trailing) {
                Menu {
                    profileActions(profile)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 12)
            }
            .contextMenu { profileActions(profile) }
        }
    }

    /// Index the dragged row would land on if released now.
    private var dragTargetIndex: Int? {
        guard let dragState else { return nil }
        let steps = Int((dragState.translation / Self.reorderRowStep).rounded())
        return max(0, min(store.profiles.count - 1, dragState.startIndex + steps))
    }

    /// How far a non-dragged row slides to make room for the dragged one.
    private func reorderShift(for index: Int) -> CGFloat {
        guard let dragState, let target = dragTargetIndex, index != dragState.startIndex
        else { return 0 }
        if dragState.startIndex < index, target >= index { return -Self.reorderRowStep }
        if index < dragState.startIndex, target <= index { return Self.reorderRowStep }
        return 0
    }

    /// Full-size fixed-height row shown in reorder mode. Rows stay static
    /// (only shifting to make room); a ghost copy follows the cursor.
    private func reorderRow(_ profile: CustomProfile, index: Int) -> some View {
        let isDragged = dragState?.id == profile.id
        return reorderRowVisual(profile)
            .opacity(isDragged ? 0.25
                     : profile.placements(matching: service.displays) != nil ? 1 : 0.5)
            .offset(y: reorderShift(for: index))
            .animation(.easeInOut(duration: 0.15), value: dragTargetIndex)
            .overlay(alignment: .trailing) {
                Color.clear
                    .frame(width: 44, height: 54)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                if dragState == nil {
                                    guard let start = store.profiles.firstIndex(where: { $0.id == profile.id })
                                    else { return }
                                    dragState = (profile.id, start, 0)
                                }
                                dragState?.translation = value.translation.height
                            }
                            .onEnded { _ in
                                if let dragState, let target = dragTargetIndex {
                                    store.move(id: dragState.id, toIndex: target)
                                }
                                dragState = nil
                            }
                    )
            }
    }

    private func reorderRowVisual(_ profile: CustomProfile) -> some View {
        HStack(spacing: 10) {
            ArrangementThumbView(profile: profile)
                .frame(width: 72, height: 46)
            Text(profile.name)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 54)
    }

    /// Floating copy of the dragged row, following the cursor.
    @ViewBuilder
    private var dragGhost: some View {
        if let dragState,
           let profile = store.profiles.first(where: { $0.id == dragState.id }) {
            reorderRowVisual(profile)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .shadow(radius: 3, y: 1)
                .offset(y: CGFloat(dragState.startIndex) * Self.reorderRowStep + dragState.translation)
                .allowsHitTesting(false)
        }
    }

    /// What the profile needs to fit: its screen counts.
    private func subtitle(for profile: CustomProfile) -> String {
        let externals = profile.displays.filter { !$0.isBuiltin }.count
        var parts = ["\(externals) external\(externals == 1 ? "" : "s")"]
        if profile.displays.contains(where: \.isBuiltin) { parts.append("laptop") }
        return parts.joined(separator: " + ")
    }

    @ViewBuilder
    private func profileActions(_ profile: CustomProfile) -> some View {
        Button("Reorder Profiles…") {
            orderBackup = store.profiles.map(\.id)
            isReordering = true
        }
        Button("Rename…") {
            renameText = profile.name
            renameTargetID = profile.id
        }
        Button("Delete", role: .destructive) {
            store.delete(id: profile.id)
        }
    }

    private func profileButton(
        title: String, subtitle: String?, enabled: Bool,
        thumb: ArrangementThumbView, action: @escaping () -> Void
    ) -> some View {
        // Not .disabled: grayed rows must stay draggable for reordering,
        // so the click is guarded instead.
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 10) {
                thumb.frame(width: 72, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: - Save current as profile

    @ViewBuilder
    private var saveCurrentSection: some View {
        if isNamingNewProfile {
            // Live preview of what will be saved: the current arrangement.
            ProfileNameEditor(
                thumb: ArrangementThumbView(profile: .capture(name: "", displays: service.displays)),
                text: $newProfileName,
                limit: Self.nameLimit,
                onCommit: commitNewProfile,
                onCancel: {
                    isNamingNewProfile = false
                    newProfileName = ""
                }
            )
        } else {
            Button {
                newProfileName = suggestedProfileName()
                isNamingNewProfile = true
            } label: {
                Label("Save Current as Profile…", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.horizontal, 12)
        }
    }

    /// Names in the built-in convention ("Dual external, built-in right"),
    /// derived from the current arrangement; (1), (2)… appended when taken.
    private func suggestedProfileName() -> String {
        let base = Self.arrangementName(for: service.displays)
        let names = Set(store.profiles.map(\.name))
        guard names.contains(base) else { return base }
        var i = 1
        while names.contains("\(base) (\(i))") { i += 1 }
        return "\(base) (\(i))"
    }

    static func arrangementName(for displays: [DisplayInfo]) -> String {
        let externals = displays.filter { !$0.isBuiltin && $0.mirrorSourceID == nil }
        let mirrored = displays.contains { $0.mirrorSourceID != nil }
        var parts: [String] = []
        switch externals.count {
        case 0: break
        case 1: parts.append("Single external")
        case 2: parts.append("Dual external")
        case 3: parts.append("Triple external")
        default: parts.append("\(externals.count) externals")
        }
        if let builtin = displays.first(where: { $0.isBuiltin && $0.mirrorSourceID == nil }) {
            if externals.isEmpty {
                parts.append("Laptop only")
            } else {
                // Which side of the externals the laptop sits on
                // (global display space: y grows downward).
                let box = externals.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
                let dx = builtin.bounds.midX - box.midX
                let dy = builtin.bounds.midY - box.midY
                let side = abs(dy) >= abs(dx) ? (dy >= 0 ? "bottom" : "top")
                                              : (dx >= 0 ? "right" : "left")
                parts.append("built-in \(side)")
            }
        }
        if mirrored { parts.append("mirrored") }
        return parts.isEmpty ? "New Profile" : parts.joined(separator: ", ")
    }

    private func commitNewProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.add(CustomProfile.capture(name: name, displays: service.displays))
        isNamingNewProfile = false
        newProfileName = ""
        showToast("Saved “\(name)”")
    }

    private func commitRename(_ profile: CustomProfile) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.rename(id: profile.id, to: name)
        renameTargetID = nil
    }

    // MARK: - Toast & errors

    @ViewBuilder
    private var toastOverlay: some View {
        if let toastMessage {
            Text(toastMessage)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 3)
                .padding(.bottom, 44)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation { toastMessage = message }
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { toastMessage = nil }
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            errorMessage = nil
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
