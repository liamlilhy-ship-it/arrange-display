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

    private var externalCount: Int { service.displays.filter { !$0.isBuiltin }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profiles")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            ForEach(store.profiles) { profile in
                profileRow(profile)
            }

            saveCurrentSection

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            Divider()

            HStack {
                Button("Display Settings…") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
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
    private func profileRow(_ profile: CustomProfile) -> some View {
        if renameTargetID == profile.id {
            HStack(spacing: 10) {
                ArrangementThumbView(profile: profile)
                    .frame(width: 72, height: 46)
                TextField("Profile name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
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

    /// Profiles without monitor memory describe what they need; profiles
    /// with it name the hardware they restore.
    private func subtitle(for profile: CustomProfile) -> String {
        let externals = profile.displays.filter { !$0.isBuiltin }
        if !profile.remembersMonitors {
            var parts = ["Any \(externals.count) external\(externals.count == 1 ? "" : "s")"]
            if profile.displays.contains(where: \.isBuiltin) { parts.append("laptop") }
            return parts.joined(separator: " + ")
        }
        let names = externals.compactMap {
            $0.name?.replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
        }
        guard names.count == externals.count else {
            return "\(profile.displays.count) screen\(profile.displays.count == 1 ? "" : "s")"
        }
        var parts = Dictionary(grouping: names, by: { $0 })
            .sorted { $0.key < $1.key }
            .map { $0.value.count > 1 ? "\($0.key) ×\($0.value.count)" : $0.key }
        if profile.displays.contains(where: \.isBuiltin) { parts.append("MacBook") }
        return parts.joined(separator: " + ")
    }

    @ViewBuilder
    private func profileActions(_ profile: CustomProfile) -> some View {
        Button("Edit Arrangement…") {
            openWindow(id: "profile-editor", value: profile.id)
            NSApp.activate(ignoringOtherApps: true)
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
        Button(action: action) {
            HStack(spacing: 10) {
                thumb.frame(width: 72, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .lineLimit(2)
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
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: - Save current as profile

    @ViewBuilder
    private var saveCurrentSection: some View {
        if isNamingNewProfile {
            HStack(spacing: 8) {
                TextField("Profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitNewProfile)
                Button("Save", action: commitNewProfile)
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") {
                    isNamingNewProfile = false
                    newProfileName = ""
                }
            }
            .padding(.horizontal, 12)
        } else {
            Button {
                isNamingNewProfile = true
            } label: {
                Label("Save Current as Profile…", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.horizontal, 12)
        }
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
