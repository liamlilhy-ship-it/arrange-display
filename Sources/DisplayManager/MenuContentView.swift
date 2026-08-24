import ObjectiveC
import SwiftUI

/// Trims the system rim off the panel window. The outermost point of the
/// window carries a glass edge highlight the window server composites
/// above our content — a light hairline no fill of ours can cover. It is
/// clipped by the window's corner mask, so hand AppKit a mask inset by
/// that point and the rim goes with it. Clear style only: Blur wants the
/// system edge on its glass sheet.
private enum PanelRim {
    /// Width of the highlight, measured off a screenshot: two device
    /// pixels on a 2x display.
    static let inset: CGFloat = 1

    private static let selector = NSSelectorFromString("_cornerMask")
    private static var original: IMP?
    private static var trims = false

    /// Installs the mask override (once per process) and refreshes the
    /// window when the style switches.
    static func set(trims wanted: Bool, on window: NSWindow) {
        install(on: window)
        guard original != nil, wanted != trims else { return }
        trims = wanted
        let changed = NSSelectorFromString("_cornerMaskChanged")
        if window.responds(to: changed) { _ = window.perform(changed) }
    }

    /// Replaces the window class's mask getter with one that returns the
    /// inset mask while trimming, and the window's own mask otherwise.
    /// If the selector ever goes away, nothing is installed and the panel
    /// keeps its stock edge.
    private static func install(on window: NSWindow) {
        guard original == nil, let cls = object_getClass(window),
              let method = class_getInstanceMethod(cls, selector) else { return }
        original = method_getImplementation(method)
        let block: @convention(block) (AnyObject) -> NSImage? = { window in
            guard trims else {
                typealias Getter = @convention(c) (AnyObject, Selector) -> NSImage?
                guard let original else { return nil }
                return unsafeBitCast(original, to: Getter.self)(window, selector)
            }
            return insetMask
        }
        class_replaceMethod(cls, selector, imp_implementationWithBlock(block),
                            method_getTypeEncoding(method))
    }

    /// The window's own mask is a 33x33 nine-part image at radius 16 —
    /// 16pt caps around a 1pt stretched centre. Same, inset: the caps
    /// carry the margin, so it holds along the straight edges too.
    private static let insetMask: NSImage = {
        let radius: CGFloat = 16
        let image = NSImage(size: NSSize(width: 33, height: 33), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                         xRadius: radius - inset, yRadius: radius - inset).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }()
}

/// Makes the MenuBarExtra panel window transparent so the desktop shows
/// through the content's own glass sheet — the Control Center look. The
/// system panel draws its background with an effect view in the window
/// frame; hide it (but never the content's own ancestors).
struct TransparentPanel: NSViewRepresentable {
    /// Clear style trims the system rim; carried here so a style switch
    /// re-runs the update.
    var trimsRim: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { clearBackground(around: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { clearBackground(around: view) }
    }

    private func clearBackground(around view: NSView) {
        guard let window = view.window, let content = window.contentView else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        var ancestors = Set<ObjectIdentifier>()
        var cursor: NSView? = content
        while let v = cursor {
            ancestors.insert(ObjectIdentifier(v))
            cursor = v.superview
        }
        func walk(_ v: NSView) {
            let isBackdrop = v is NSVisualEffectView
                || String(describing: type(of: v)).contains("GlassEffectView")
            if isBackdrop, !ancestors.contains(ObjectIdentifier(v)) {
                v.isHidden = true
            }
            guard v !== content else { return }
            v.subviews.forEach(walk)
        }
        if let frame = content.superview { walk(frame) }
        // The window shadow carries a thin light bezel line along the edge;
        // it reads as a light ring around the sheet, so drop it.
        window.hasShadow = false
        window.invalidateShadow()
        PanelRim.set(trims: trimsRim, on: window)
    }
}

/// Control Center-style bubble: a brightened fill plus a light rim.
/// Drawn manually because glass effects don't render nested inside the
/// panel's own glass sheet. Opacities are tunable live via the temporary
/// "Tune" sliders (persisted in UserDefaults).
private struct Bubble: ViewModifier {
    var radius: CGFloat
    var highlight: Bool
    // Liam's tuned values, baked in per style (Clear has no glass sheet
    // behind it, so everything reads stronger and sits lower).
    @AppStorage("panelStyle") private var panelStyle = "blur"
    private var fill: Double { panelStyle == "clear" ? 0.015 : 0.034 }
    private var rim: Double { panelStyle == "clear" ? 0.076 : 0.030 }
    private var hover: Double { panelStyle == "clear" ? 0.040 : 0.200 }
    // Every bubble brightens under the pointer on its own.
    @State private var isHovering = false

    func body(content: Content) -> some View {
        let active = highlight || isHovering
        return content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.white.opacity(active ? hover : fill)))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(rim), .white.opacity(rim * 0.22)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                    .allowsHitTesting(false))
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: active)
    }
}

private extension View {
    func bubble(_ radius: CGFloat, highlight: Bool = false) -> some View {
        modifier(Bubble(radius: radius, highlight: highlight))
    }
}

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
    @Binding var warning: String?
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
                        warning = nil
                        if new.count > limit { text = String(new.prefix(limit)) }
                    }

                if let warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.red)
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
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    // Inline "save current as profile" naming state.
    @State private var isNamingNewProfile = false
    @State private var newProfileName = ""

    // Inline rename state for custom profiles.
    @State private var renameTargetID: UUID?
    @State private var renameText = ""

    // Duplicate-name warning shown in whichever name editor is open.
    @State private var nameWarning: String?

    // Row under the pointer, for the menu-style hover highlight.
    @State private var hoveredID: UUID?
    // Row whose … icon is under the pointer, for its own circle highlight.
    @State private var hoveredMenuID: UUID?

    // Settings: panel style and per-style frost levels (0–10), plus UI
    // language. "blur" is the glass sheet with a white wash; "clear"
    // drops the glass entirely: a black dim wash and forced white text.
    // Defaults are Liam's tuned values.
    static let frostDefault = 1.0
    static let clearDimDefault = 8.2
    @AppStorage("panelStyle") private var panelStyle = "blur"
    @AppStorage("frostLevel") private var frost = 1.0
    @AppStorage("clearDimLevel") private var clearDim = 8.2
    @AppStorage("language") private var language = "en"
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @State private var showingSettings =
        ProcessInfo.processInfo.environment["DM_OPEN_SETTINGS"] != nil

    // Reorder mode: entered from a row's ... menu; rows show drag handles.
    // The dragged row floats with the finger; neighbors shift; the array
    // reorders once, on release — live array moves mid-drag cause jitter.
    // Debug: DM_REORDER=1 opens in reorder mode, for screenshots.
    @State private var isReordering =
        ProcessInfo.processInfo.environment["DM_REORDER"] != nil
    @State private var dragState: (id: UUID, startIndex: Int, translation: CGFloat)?
    @State private var orderBackup: [UUID] = []

    /// Roomy enough for auto-suggested names with a (n) suffix; names
    /// longer than two row lines truncate with an ellipsis.
    private static let nameLimit = 45
    /// Fixed reorder-row height (54) plus the VStack spacing (8).
    private static let reorderRowStep: CGFloat = 62

    private var externalCount: Int { service.displays.filter { !$0.isBuiltin }.count }

    private var isClearStyle: Bool { panelStyle == "clear" }

    var body: some View {
        styledPanel
        .background(TransparentPanel(trimsRim: isClearStyle))
        // Debug: DM_TOAST=<text> shows a toast on open, for screenshots.
        .onAppear {
            if let text = ProcessInfo.processInfo.environment["DM_TOAST"] {
                showToast(text)
            }
        }
    }

    /// The panel sheet in the selected style. Blur: white frost wash over
    /// a glass sheet, so the desktop blurs through — Control Center style.
    /// Clear: no glass at all, a black dim wash, and dark-mode (white)
    /// text regardless of the system appearance.
    @ViewBuilder
    private var styledPanel: some View {
        let base = Group {
            if showingSettings {
                settingsContent
            } else {
                mainContent
            }
        }
        .frame(width: 300)

        if isClearStyle {
            base
                .environment(\.colorScheme, .dark)
                // The panel window's own corner radius is 16 (its private
                // _cornerMask is a 33×33 image), smaller than the 22 the
                // Blur sheet uses. Match it — outset 4pt at radius 20 so
                // the fill reaches every corner tip; the window shape clips
                // the excess. Otherwise the system sheet peeks out as a
                // light frame.
                .background(RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(clearDim * 0.06))
                    .padding(-4))
        } else {
            base
                .background(RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(frost * 0.06)))
                .glassEffect(.clear, in: .rect(cornerRadius: 22))
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Presets", "配置"))
                    .font(.headline)
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            toastBanner

            // Liquid Glass: rows are standalone glass cards. No
            // GlassEffectContainer — it lifts glass above sibling overlays,
            // which hid each row's … menu.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                    profileRow(profile, index: index)
                }
            }
            .overlay(alignment: .topTrailing) { reorderHotkeyColumn }
            .overlay(alignment: .top) { dragGhost }

            if isReordering {
                HStack {
                    Text(L("Drag the handles to reorder", "拖动手柄调整顺序"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Reset", "重置")) { store.setOrder(orderBackup) }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .bubble(999)
                    Button(L("Done", "完成")) { isReordering = false }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .bubble(999)
                }
                .padding(.horizontal, 12)
            } else {
                currentSection
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            Divider()

            HStack {
                Button(action: openDisplaySettings) {
                    Text(L("Display Settings…", "显示器设置…"))
                        .padding(.vertical, 4).padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
                .bubble(999)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text(L("Quit", "退出"))
                        .padding(.vertical, 4).padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
                .bubble(999)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Settings

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    showingSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text(L("Settings", "设置"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            toastBanner

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Style", "样式"))
                    .font(.subheadline)
                Picker("", selection: $panelStyle) {
                    Text(L("Blur", "模糊")).tag("blur")
                    Text(L("Clear", "透明")).tag("clear")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(L("Frost", "磨砂"))
                    .font(.subheadline)
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    Slider(value: activeFrost, in: 0...10)
                    Text(String(format: "%.1f", activeFrost.wrappedValue))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                HStack {
                    Spacer()
                    Button(L("Default", "默认")) {
                        activeFrost.wrappedValue =
                            isClearStyle ? Self.clearDimDefault : Self.frostDefault
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4).padding(.horizontal, 10)
                    .bubble(999)
                }
            }
            .padding(10)
            .bubble(16)
            .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(L("Launch at login", "登录时自动启动"), isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.sync(enabled: enabled)
                    }
            }
            .padding(10)
            .bubble(16)
            .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Updates", "更新"))
                    .font(.subheadline)
                HStack {
                    Text(L("Version \(Updater.currentVersion)",
                           "版本 \(Updater.currentVersion)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Check for Updates…", "检查更新…")) {
                        Updater.checkNow()
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4).padding(.horizontal, 10)
                    .bubble(999)
                }
            }
            .padding(10)
            .bubble(16)
            .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Language", "语言"))
                    .font(.subheadline)
                Picker("", selection: $language) {
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(10)
            .bubble(16)
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 10)
    }

    /// The frost slider drives only the selected style's level.
    private var activeFrost: Binding<Double> {
        Binding(
            get: { isClearStyle ? clearDim : frost },
            set: { if isClearStyle { clearDim = $0 } else { frost = $0 } })
    }

    private func L(_ en: String, _ zh: String) -> String {
        language == "zh" ? zh : en
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
                warning: $nameWarning,
                limit: Self.nameLimit,
                onCommit: { commitRename(profile) },
                onCancel: {
                    renameTargetID = nil
                    nameWarning = nil
                }
            )
            .padding(.vertical, 4)
        } else {
            let applicable = profile.placements(matching: service.displays) != nil
            profileButton(
                title: profile.name,
                subtitle: subtitle(for: profile),
                shortcut: HotkeyManager.label(forIndex: index),
                enabled: applicable,
                hovered: hoveredID == profile.id,
                thumb: ArrangementThumbView(profile: profile)
            ) {
                guard !isReordering else { return }
                attempt {
                    try service.apply(profile: profile)
                    showToast(L("Applied “\(profile.name)”", "已应用“\(profile.name)”"))
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
                .padding(3)
                .background(
                    Circle().fill(Color.white.opacity(hoveredMenuID == profile.id ? 0.35 : 0)))
                .animation(.easeInOut(duration: 0.12), value: hoveredMenuID)
                .onHover { hoveredMenuID = $0 ? profile.id : nil }
                .padding(.trailing, 15)
            }
            // After the overlay, so the row highlight holds while the
            // pointer is on the … icon.
            .onHover { hoveredID = $0 ? profile.id : nil }
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
            .bubble(16)
            .opacity(isDragged ? 0.25
                     : profile.placements(matching: service.displays) != nil ? 1 : 0.5)
            .padding(.horizontal, 10)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 54)
    }

    /// Fixed ⌃⌘n column shown while reordering. It sits outside the rows,
    /// so the badges stay glued to their slots while rows move — showing
    /// that hotkeys belong to positions, not to presets.
    @ViewBuilder
    private var reorderHotkeyColumn: some View {
        if isReordering {
            VStack(spacing: 8) {
                ForEach(0..<store.profiles.count, id: \.self) { index in
                    Text(HotkeyManager.label(forIndex: index) ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(height: 54)
                }
            }
            .padding(.trailing, 48)
            .allowsHitTesting(false)
        }
    }

    /// Floating copy of the dragged row, following the cursor.
    @ViewBuilder
    private var dragGhost: some View {
        if let dragState,
           let profile = store.profiles.first(where: { $0.id == dragState.id }) {
            reorderRowVisual(profile)
                .bubble(16)
                .shadow(radius: 3, y: 1)
                .padding(.horizontal, 10)
                .offset(y: CGFloat(dragState.startIndex) * Self.reorderRowStep + dragState.translation)
                .allowsHitTesting(false)
        }
    }

    /// What the profile needs to fit: its screen counts.
    private func subtitle(for profile: CustomProfile) -> String {
        let externals = profile.displays.filter { !$0.isBuiltin }.count
        var parts = [language == "zh" ? "\(externals) 个外接屏"
                                      : "\(externals) external\(externals == 1 ? "" : "s")"]
        if profile.displays.contains(where: \.isBuiltin) {
            parts.append(L("laptop", "笔记本"))
        }
        return parts.joined(separator: " + ")
    }

    @ViewBuilder
    private func profileActions(_ profile: CustomProfile) -> some View {
        Button(L("Reorder", "排序")) {
            orderBackup = store.profiles.map(\.id)
            isReordering = true
        }
        Button(L("Rename", "重命名")) {
            renameText = profile.name
            renameTargetID = profile.id
        }
        Button(L("Delete", "删除"), role: .destructive) {
            store.delete(id: profile.id)
        }
    }

    private func profileButton(
        title: String, subtitle: String?, shortcut: String?, enabled: Bool, hovered: Bool,
        thumb: ArrangementThumbView, action: @escaping () -> Void
    ) -> some View {
        // Not .disabled: grayed rows must stay draggable for reordering,
        // so the click is guarded instead.
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 10) {
                thumb.frame(width: 72, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    // Fixed size: long names wrap to two lines, then
                    // truncate — the font never shrinks.
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

                // Hotkey badge, with breathing room before the … menu.
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 26)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .bubble(16, highlight: hovered)
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .opacity(enabled ? 1 : 0.4)
        .padding(.horizontal, 10)
    }

    // MARK: - Current arrangement

    /// "Current" section: a live thumbnail of what the screens look like
    /// right now (no bubble, no name), with the connection status and the
    /// save button beside it; only the save button highlights on hover.
    private var currentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Current", "当前"))
                .font(.headline)
                .padding(.horizontal, 12)
            // While naming, the editor's live thumbnail already shows the
            // current arrangement, so the card would be a duplicate.
            if isNamingNewProfile {
                saveCurrentSection
            } else {
                currentRow
            }
        }
    }

    private var currentRow: some View {
        HStack(spacing: 10) {
            ArrangementThumbView(profile: .capture(name: "", displays: service.displays))
                .frame(width: 72, height: 46)

            // Nudged right of the preset names' alignment line.
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    newProfileName = suggestedProfileName()
                    isNamingNewProfile = true
                } label: {
                    Label(L("Save as Preset…", "存为配置…"), systemImage: "plus.circle")
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
                .bubble(999)

                connectionStatus
                    .padding(.leading, 10)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    /// Connection status: two fixed lines — the external count and the
    /// laptop screen — with a green dot when present, gray when not
    /// (e.g. clamshell mode). Secondary captions read in both styles.
    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 3) {
            statusLine(
                on: externalCount > 0,
                text: language == "zh" ? "\(externalCount) 个外接屏"
                                       : "\(externalCount) external\(externalCount == 1 ? "" : "s")")
            statusLine(
                on: service.displays.contains(where: \.isBuiltin),
                text: L("Laptop", "笔记本"))
        }
    }

    private func statusLine(on: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(on ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Save current as profile

    /// Naming editor shown in place of the current-arrangement card;
    /// its live thumbnail is the preview of what will be saved.
    private var saveCurrentSection: some View {
        ProfileNameEditor(
            thumb: ArrangementThumbView(profile: .capture(name: "", displays: service.displays)),
            text: $newProfileName,
            warning: $nameWarning,
            limit: Self.nameLimit,
            onCommit: commitNewProfile,
            onCancel: {
                isNamingNewProfile = false
                newProfileName = ""
                nameWarning = nil
            }
        )
    }

    /// Names in the built-in convention ("2 externals, built-in right"),
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
        case 1: parts.append("1 external")
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
        return parts.isEmpty ? "New Preset" : parts.joined(separator: ", ")
    }

    private func commitNewProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard isNameFree(name) else {
            nameWarning = L("A preset with this name already exists", "已存在同名配置")
            return
        }
        store.add(CustomProfile.capture(name: name, displays: service.displays))
        isNamingNewProfile = false
        newProfileName = ""
        showToast(L("Saved “\(name)”", "已保存“\(name)”"))
    }

    private func commitRename(_ profile: CustomProfile) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard isNameFree(name, excluding: profile.id) else {
            nameWarning = L("A preset with this name already exists", "已存在同名配置")
            return
        }
        store.rename(id: profile.id, to: name)
        renameTargetID = nil
    }

    private func isNameFree(_ name: String, excluding id: UUID? = nil) -> Bool {
        !store.profiles.contains { $0.id != id && $0.name == name }
    }


    /// Opens System Settings on the Displays pane. Clicking through to the
    /// Arrange sheet would need UI scripting and an Automation permission
    /// prompt, so it stops here — friction-free.
    private func openDisplaySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
    }

    // MARK: - Toast & errors

    /// Inline banner at the top of the panel: takes its own layout space
    /// (pushing content down) so it never covers other text.
    @ViewBuilder
    private var toastBanner: some View {
        if let toastMessage {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(toastMessage)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .bubble(999)
            .padding(.horizontal, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
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
