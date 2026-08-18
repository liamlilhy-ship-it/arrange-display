import AppKit
import CoreGraphics
import Foundation

final class DisplayService: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []

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

        return ids.prefix(Int(count)).map { id in
            var uuid = ""
            if let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
               let str = CFUUIDCreateString(nil, cfUUID) {
                uuid = str as String
            }
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
            }
            let mirrorSource = CGDisplayMirrorsDisplay(id)
            return DisplayInfo(
                id: id,
                uuid: uuid,
                name: screen?.localizedName ?? "Display \(id)",
                bounds: CGDisplayBounds(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                mirrorSourceID: mirrorSource == kCGNullDirectDisplay ? nil : mirrorSource,
                mode: CGDisplayCopyDisplayMode(id).map(spec)
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
        try Self.apply(placements: placements)
        refresh()
    }

    func apply(profile: CustomProfile) throws {
        guard let placements = profile.placements(matching: displays) else { return }
        try Self.apply(placements: placements)
        refresh()
    }

    static func apply(placements: [Placement]) throws {
        var config: CGDisplayConfigRef?
        let err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { throw ApplyError.configurationFailed(err) }

        func check(_ err: CGError) throws {
            guard err == .success else {
                CGCancelDisplayConfiguration(config)
                throw ApplyError.configurationFailed(err)
            }
        }
        // Restore display modes first: the saved origins were captured under
        // these modes, and a mode change alters the display's point size.
        // A mode that's no longer offered is skipped — the arrangement is
        // never held hostage by the mode.
        for p in placements {
            guard let spec = p.mode else { continue }
            if let current = CGDisplayCopyDisplayMode(p.displayID), Self.spec(current).matches(spec) {
                continue
            }
            let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
            guard let all = CGDisplayCopyAllDisplayModes(p.displayID, options) as? [CGDisplayMode],
                  let target = all.first(where: { Self.spec($0).matches(spec) })
            else { continue }
            _ = CGConfigureDisplayWithDisplayMode(config, p.displayID, target, nil)
        }
        // Then mirror state for every display (kCGNullDirectDisplay = extended),
        // then origins for the extended ones.
        for p in placements {
            try check(CGConfigureDisplayMirrorOfDisplay(config, p.displayID, p.mirrorOf ?? kCGNullDirectDisplay))
        }
        for p in placements where p.mirrorOf == nil {
            try check(CGConfigureDisplayOrigin(config, p.displayID, p.x, p.y))
        }
        try check(CGCompleteDisplayConfiguration(config, .permanently))
    }

    static func spec(_ mode: CGDisplayMode) -> ModeSpec {
        ModeSpec(pixelWidth: Int32(mode.pixelWidth), pixelHeight: Int32(mode.pixelHeight),
                 pointWidth: Int32(mode.width), pointHeight: Int32(mode.height),
                 refreshRate: mode.refreshRate)
    }
}
