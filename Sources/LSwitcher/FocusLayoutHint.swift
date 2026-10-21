import AppKit
@preconcurrency import ApplicationServices
import Carbon
import LSwitcherCore

private final class HintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A click-through indicator. It reads role and bounds, never AXValue/text.
@MainActor
final class FocusLayoutHint {
    private let panel: HintPanel
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var element: AXUIElement?
    private var pid: pid_t = 0
    private var observer: AXObserver?
    private var observerPID: pid_t = 0
    private var state = FocusHintState()
    private(set) var visible = false

    init() {
        panel = HintPanel(contentRect: NSRect(x: 0, y: 0, width: 34, height: 26),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 34, height: 26))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true
        label.frame = NSRect(x: 2, y: 1, width: 30, height: 24)
        label.font = .systemFont(ofSize: 18)
        label.alignment = .center
        label.setAccessibilityElement(false)
        background.addSubview(label)
        panel.contentView = background
    }

    func setAllowed(_ allowed: Bool) {
        guard allowed else {
            timer?.invalidate(); timer = nil; stopObserving(); reset(); return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.04
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh()
    }
    func reset() { element = nil; pid = 0; state.reset(); hide() }
    func didType() { state.didType(); hide() }
    private func hide() { if panel.isVisible { panel.orderOut(nil) }; visible = false }

    func refresh() {
        guard Preferences.shared.enabled, Preferences.shared.showLayoutHint, AXIsProcessTrusted(),
              !IsSecureEventInputEnabled(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !(app.bundleIdentifier ?? "").hasPrefix("com.1password."),
              app.bundleIdentifier != "com.agilebits.onepassword7",
              let focused = AccessibilityFocus.element(app: app, timeout: 0.02).element else {
            element = nil; hide(); return
        }
        var owner: pid_t = 0
        guard AXUIElementGetPid(focused, &owner) == .success, owner > 0 else { hide(); return }
        observe(owner)
        let changed = pid != owner || element.map { !CFEqual($0, focused) } != false
        pid = owner
        element = focused
        var role: CFTypeRef?, subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subrole)
        guard ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role as? String ?? ""),
              subrole as? String != "AXSecureTextField" else { hide(); return }
        var editable = DarwinBoolean(false)
        var flag: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, "AXEditable" as CFString, &flag)
        guard flag as? Bool == true ||
              (AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &editable) == .success && editable.boolValue),
              state.shouldShow(focusChanged: changed), let frame = bounds(focused),
              let primary = NSScreen.screens.first else { hide(); return }
        // AX coordinates start at the top-left of the primary display.
        let cocoa = NSRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        guard let display = NSScreen.screens.first(where: { $0.frame.intersects(cocoa) }) else { hide(); return }
        let area = display.visibleFrame.insetBy(dx: 4, dy: 4)
        let x = min(max(cocoa.maxX + 5, area.minX), area.maxX - 34)
        let y = min(max(cocoa.maxY - 26, area.minY), area.maxY - 26)
        label.stringValue = Self.currentSymbol()
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        if !panel.isVisible { panel.orderFrontRegardless() }
        visible = true
    }

    private func stopObserving() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; observerPID = 0
    }
    private func observe(_ process: pid_t) {
        guard process > 0, process != observerPID else { return }
        stopObserving()
        var created: AXObserver?
        guard AXObserverCreate(process, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<FocusLayoutHint>.fromOpaque(context).takeUnretainedValue().refresh()
            }
        }, &created) == .success, let created else { return }
        let root = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(root, 0.02)
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, root, kAXFocusedUIElementChangedNotification as CFString, context)
        AXObserverAddNotification(created, root, kAXFocusedWindowChangedNotification as CFString, context)
        observer = created; observerPID = process
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    private func bounds(_ field: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(field, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    static func currentSymbol() -> String { CurrentLayout.presentation.flag }
}
