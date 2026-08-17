import SwiftUI

struct MenuContentView: View {
    @ObservedObject var service: DisplayService
    @State private var errorMessage: String?

    private var externalCount: Int { service.displays.filter { !$0.isBuiltin }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arrangement Profiles")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            ForEach(Preset.allCases) { preset in
                presetRow(preset)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            Divider()

            HStack {
                Button("Restore Previous") {
                    attempt { try service.restorePrevious() }
                }
                .disabled(service.previousArrangement == nil)

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
    }

    @ViewBuilder
    private func presetRow(_ preset: Preset) -> some View {
        let placements = PresetLayouts.placements(for: preset, displays: service.displays)
        let isActive = PresetLayouts.isActive(preset, displays: service.displays)

        Button {
            attempt { try service.apply(preset: preset) }
        } label: {
            HStack(spacing: 10) {
                ArrangementThumbView(placements: placements ?? PresetLayouts.genericPlacements(for: preset))
                    .frame(width: 72, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.body)
                    Text("Needs \(preset.requiredExternalCount) external\(preset.requiredExternalCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(placements == nil)
        .opacity(placements == nil ? 0.4 : 1)
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
