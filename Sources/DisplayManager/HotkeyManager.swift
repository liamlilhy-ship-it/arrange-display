import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Global ⌃⌘1–⌃⌘9 hotkeys that apply presets by their menu order
/// (⌃⌘1 = top preset). Carbon RegisterEventHotKey works system-wide
/// without any Accessibility/Automation permission prompt.
final class HotkeyManager {
    /// The hotkey label shown in the menu for a row index, nil past ⌃⌘9.
    static func label(forIndex index: Int) -> String? {
        index < 9 ? "⌃⌘\(index + 1)" : nil
    }

    private let store: ProfileStore
    private let service: DisplayService
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    /// Virtual key codes for the 1–9 number-row keys (kVK_ANSI_1…9).
    private static let numberKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
    ]

    init(store: ProfileStore, service: DisplayService) {
        self.store = store
        self.service = service

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                Unmanaged<HotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .apply(index: Int(hotKeyID.id) - 1)
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let signature = OSType(0x444D_4859) // 'DMHY'
        for (index, keyCode) in Self.numberKeyCodes.enumerated() {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(
                keyCode, UInt32(controlKey | cmdKey),
                EventHotKeyID(signature: signature, id: UInt32(index + 1)),
                GetEventDispatcherTarget(), 0, &ref)
            if let ref { hotKeyRefs.append(ref) }
        }
    }

    private func apply(index: Int) {
        guard store.profiles.indices.contains(index) else { return }
        let profile = store.profiles[index]
        // Same guard as the menu row: ignore presets that don't fit the
        // currently connected screens.
        guard profile.placements(matching: service.displays) != nil else { return }
        guard (try? service.apply(profile: profile)) != nil else { return }
        let zh = UserDefaults.standard.string(forKey: "language") == "zh"
        let message = zh ? "已应用“\(profile.name)”" : "Applied “\(profile.name)”"
        Task { @MainActor in HotkeyToast.show(message) }
    }
}

/// Floating confirmation shown when a hotkey applies a preset while the
/// menu is closed: a borderless, non-activating HUD panel under the menu
/// bar that fades out on its own. No notification permission involved.
@MainActor
enum HotkeyToast {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String) {
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let content = NSHostingView(rootView:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .lineLimit(1)
            }
            .font(.callout)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        )
        content.setFrameSize(content.fittingSize)

        // Behind-window blur so the pill reads as a system HUD; SwiftUI
        // materials can't sample behind their own window.
        let effect = NSVisualEffectView(frame: content.frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = content.frame.height / 2
        effect.layer?.masksToBounds = true
        effect.addSubview(content)

        let toast = NSPanel(
            contentRect: content.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        toast.level = .statusBar
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        toast.ignoresMouseEvents = true
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toast.contentView = effect

        // Top-center of the screen the user is working on.
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let area = screen.visibleFrame
            toast.setFrameOrigin(NSPoint(
                x: area.midX - content.frame.width / 2,
                y: area.maxY - content.frame.height - 12))
        }
        toast.orderFrontRegardless()
        panel = toast

        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                toast.animator().alphaValue = 0
            } completionHandler: {
                toast.orderOut(nil)
            }
        }
    }
}
