import SwiftUI

/// The single editing entrance: a window listing every profile in a sidebar,
/// with the arrangement editor for the selected one in the detail pane.
struct ProfileManagerView: View {
    @ObservedObject var store: ProfileStore
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(store.profiles, selection: $selection) { profile in
                HStack(spacing: 8) {
                    ArrangementThumbView(profile: profile)
                        .frame(width: 48, height: 30)
                    Text(profile.name)
                        .lineLimit(1)
                }
                .tag(profile.id)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            if let selection, store.profiles.contains(where: { $0.id == selection }) {
                // .id() rebuilds the editor's state when the selection changes.
                ProfileEditorView(store: store, profileID: selection)
                    .id(selection)
            } else {
                Text("Select a profile to edit")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if selection == nil { selection = store.profiles.first?.id }
        }
    }
}
