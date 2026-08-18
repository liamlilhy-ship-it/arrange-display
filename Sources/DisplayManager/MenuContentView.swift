import SwiftUI

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

            ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                profileRow(profile, index: index)
            }

            if isReordering {
                HStack {
                    Text("Drag the handles to reorder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
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
            HStack(spacing: 10) {
                ArrangementThumbView(profile: profile)
                    .frame(width: 72, height: 46)
                TextField("Profile name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: renameText) { _, new in
                        if new.count > Self.nameLimit {
                            renameText = String(new.prefix(Self.nameLimit))
                        }
                    }
                    .onSubmit { commitRename(profile) }
                Button("Save") { commitRename(profile) }
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
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

    /// Full-size fixed-height row shown in reorder mode.
    private func reorderRow(_ profile: CustomProfile, index: Int) -> some View {
        let isDragged = dragState?.id == profile.id
        return HStack(spacing: 10) {
            ArrangementThumbView(profile: profile)
                .frame(width: 72, height: 46)
            Text(profile.name)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle().inset(by: -10))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 54)
        .background(isDragged ? Color.secondary.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .opacity(profile.placements(matching: service.displays) != nil ? 1 : 0.5)
        .offset(y: isDragged ? (dragState?.translation ?? 0) : reorderShift(for: index))
        .zIndex(isDragged ? 1 : 0)
        .animation(isDragged ? nil : .easeInOut(duration: 0.15), value: dragTargetIndex)
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
        Button("Reorder Profiles…") { isReordering = true }
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
            HStack(alignment: .top, spacing: 10) {
                // Live preview of what will be saved: the current arrangement.
                ArrangementThumbView(profile: .capture(name: "", displays: service.displays))
                    .frame(width: 72, height: 46)

                VStack(alignment: .leading, spacing: 6) {
                    // Plain style grows with its content; roundedBorder keeps
                    // a fixed height in this panel.
                    TextField("Profile name", text: $newProfileName, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                        .onChange(of: newProfileName) { _, new in
                            if new.count > Self.nameLimit {
                                newProfileName = String(new.prefix(Self.nameLimit))
                            }
                        }
                        .onSubmit(commitNewProfile)

                    HStack(spacing: 10) {
                        Text("\(newProfileName.count)/\(Self.nameLimit)")
                            .font(.caption2)
                            .foregroundStyle(newProfileName.count >= Self.nameLimit ? .red : .secondary)
                        Spacer()
                        Button(action: commitNewProfile) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button {
                            isNamingNewProfile = false
                            newProfileName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
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
