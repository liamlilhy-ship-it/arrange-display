import AppKit
import CoreGraphics
import Foundation

final class DisplayService: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var previousArrangement: [Placement]?

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        displays = Self.currentDisplays()
    }

    static func currentDisplays() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }

        return ids.prefix(Int(count)).compactMap { id in
            // Skip displays that are mirroring another display.
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay else { return nil }
            var uuid = ""
            if let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
               let str = CFUUIDCreateString(nil, cfUUID) {
                uuid = str as String
            }
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
            }
            return DisplayInfo(
                id: id,
                uuid: uuid,
                name: screen?.localizedName ?? "Display \(id)",
                bounds: CGDisplayBounds(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0
            )
        }
    }

    enum ApplyError: LocalizedError {
        case configurationFailed(CGError)
        var errorDescription: String? {
            switch self {
            case .configurationFailed(let err): return "Display configuration failed (CGError \(err.rawValue))"
            }
        }
    }

    func apply(preset: Preset) throws {
        guard let target = PresetLayouts.placements(for: preset, displays: displays) else { return }
        let placements = target.map {
            Placement(displayID: $0.display.id, x: Int32($0.origin.x.rounded()), y: Int32($0.origin.y.rounded()))
        }
        let snapshot = displays.map {
            Placement(displayID: $0.id, x: Int32($0.bounds.origin.x), y: Int32($0.bounds.origin.y))
        }
        try Self.apply(placements: placements)
        previousArrangement = snapshot
        refresh()
    }

    func restorePrevious() throws {
        guard let previous = previousArrangement else { return }
        try Self.apply(placements: previous)
        previousArrangement = nil
        refresh()
    }

    static func apply(placements: [Placement]) throws {
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { throw ApplyError.configurationFailed(err) }
        for p in placements {
            err = CGConfigureDisplayOrigin(config, p.displayID, p.x, p.y)
            guard err == .success else {
                CGCancelDisplayConfiguration(config)
                throw ApplyError.configurationFailed(err)
            }
        }
        err = CGCompleteDisplayConfiguration(config, .permanently)
        guard err == .success else { throw ApplyError.configurationFailed(err) }
    }
}
