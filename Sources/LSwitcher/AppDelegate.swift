import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var enabledItem: NSMenuItem!
    private var autoItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()
        model = AppModel()
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        let image = NSImage(size: NSSize(width: 22, height: 19), flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.65
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 3, y: 13)); path.line(to: NSPoint(x: 18, y: 13))
            path.move(to: NSPoint(x: 14, y: 17)); path.line(to: NSPoint(x: 18, y: 13)); path.line(to: NSPoint(x: 14, y: 9))
            path.move(to: NSPoint(x: 19, y: 6)); path.line(to: NSPoint(x: 4, y: 6))
            path.move(to: NSPoint(x: 8, y: 10)); path.line(to: NSPoint(x: 4, y: 6)); path.line(to: NSPoint(x: 8, y: 2))
            path.stroke()
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.addItem(withTitle: "LSwitcher", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        enabledItem = menu.addItem(withTitle: "Переключение включено", action: #selector(toggleEnabled), keyEquivalent: "")
        autoItem = menu.addItem(withTitle: "Автоисправление", action: #selector(toggleAutomatic), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "О программе…", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Выход", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        model.changed = { [weak self] in self?.refreshMenu() }
        refreshMenu()
        showSettings()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: name, object: nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    private func installEditMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Завершить LSwitcher", action: #selector(quit), keyEquivalent: "q").target = self
        menu.addItem(appItem)
        let edit = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "Правка")
        for (title, action, key) in [("Отменить", Selector(("undo:")), "z"),
            ("Вырезать", #selector(NSText.cut(_:)), "x"), ("Копировать", #selector(NSText.copy(_:)), "c"),
            ("Вставить", #selector(NSText.paste(_:)), "v"), ("Выделить всё", #selector(NSText.selectAll(_:)), "a")] {
            edit.submenu?.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }
    private func refreshMenu() {
        enabledItem?.state = model.enabled ? .on : .off
        autoItem?.state = model.automatic ? .on : .off
        statusItem?.button?.appearsDisabled = !model.enabled || !model.ready
        statusItem?.button?.toolTip = model.ready ? "LSwitcher · Shift × 2" : "LSwitcher · Проверьте разрешения"
    }
    @objc private func willSleep() { model.engine.suspend(); model.focusHint.setAllowed(false) }
    @objc private func didWake() { model.engine.reset(); model.retry() }
    @objc private func applicationChanged() { model.engine.reset(); model.focusHint.reset(); AccessibilityFocus.prepare(NSWorkspace.shared.frontmostApplication) }
    @objc private func toggleEnabled() { model.setEnabled(!model.enabled) }
    @objc private func toggleAutomatic() { model.setAutomatic(!model.automatic) }
    @objc private func showAbout() { model.page = .about; showSettings() }
    @objc private func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "LSwitcher"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 880, height: 670)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
