@preconcurrency import ApplicationServices
import Foundation
import AppKit

enum AccessibilityFocus {
    @MainActor private static var preparedChromium = Set<pid_t>()
    @MainActor static func resetPreparation() { preparedChromium.removeAll() }
    @MainActor static func prepare(_ app: NSRunningApplication?) {
        guard AXIsProcessTrusted(), let app, app.processIdentifier > 0,
              ["com.google.Chrome", "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser", "com.termius-dmg.mac", "com.termius.mac"].contains(app.bundleIdentifier ?? ""),
              !preparedChromium.contains(app.processIdentifier) else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.1)
        // Chromium's supported assistive-technology activation signal. It can
        // take two seconds to expose focused web fields after the first request.
        if AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) == .success {
            preparedChromium.insert(app.processIdentifier)
        }
    }

    /// The owner of system-wide keyboard focus is authoritative for nonactivating
    /// panels such as system search. NSWorkspace can still name the app behind them.
    static func keyboardApplication(timeout: Float) -> NSRunningApplication? {
        let foreground = NSWorkspace.shared.frontmostApplication
        let root = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return foreground }
        var pid: pid_t = 0
        guard AXUIElementGetPid(unsafeDowncast(value, to: AXUIElement.self), &pid) == .success,
              pid > 0, let owner = NSRunningApplication(processIdentifier: pid),
              owner.bundleIdentifier != nil else { return foreground }
        return owner
    }

    static func isSearchField(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?, subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        return subrole as? String == kAXSearchFieldSubrole as String || role as? String == "AXSearchField"
    }

    static func description(app: NSRunningApplication, element: AXUIElement?) -> String {
        var role: CFTypeRef?, subrole: CFTypeRef?
        if let element {
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        }
        return "\(app.bundleIdentifier ?? "—") · \(role as? String ?? "—") / \(subrole as? String ?? "—")"
    }

    /// Resolve actual keyboard focus rather than relying exclusively on a cached
    /// NSWorkspace application object during activation or a document launch.
    static func element(app: NSRunningApplication, timeout: Float) -> (element: AXUIElement?, error: AXError) {
        let pid = app.processIdentifier
        var lastError: AXError = .noValue
        var roots = [AXUIElementCreateSystemWide()]
        if pid > 0 { roots.append(AXUIElementCreateApplication(pid)) }
        for root in roots {
            AXUIElementSetMessagingTimeout(root, timeout)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value)
            lastError = error
            guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            let element = unsafeDowncast(value, to: AXUIElement.self)
            var owner: pid_t = 0
            guard AXUIElementGetPid(element, &owner) == .success, owner > 0 else { lastError = .invalidUIElement; continue }
            // NSRunningApplication explicitly permits PID -1. In that case resolve
            // the owner from AX instead of constructing an invalid application root.
            let matches = pid > 0 ? owner == pid :
                NSRunningApplication(processIdentifier: owner)?.bundleIdentifier == app.bundleIdentifier
            guard matches else { lastError = .noValue; continue }
            AXUIElementSetMessagingTimeout(element, timeout)
            return (element, .success)
        }
        return (nil, lastError)
    }
}
