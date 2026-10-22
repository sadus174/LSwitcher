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
