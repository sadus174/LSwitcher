import AppKit
import SwiftUI
import Carbon
import LSwitcherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var enabledItem: NSMenuItem!
    private var autoItem: NSMenuItem!
    private var defaultStatusImage: NSImage?
    private var recoveryTask: Task<Void, Never>?
    private(set) var statusGeneration = 1
    var statusItemPresent: Bool { statusItem?.isVisible == true && statusItem?.button != nil && statusItem?.menu != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()
        model = AppModel()
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        statusItem.autosaveName = "LSwitcher.StatusItem"
        statusItem.isVisible = true
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
        defaultStatusImage = image
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
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(layoutChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        showSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemAppLaunched), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: name, object: nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { recreateStatusItem(); model.retry(); showSettings(); return true }
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
        guard let button = statusItem?.button else { return }
        let layout = CurrentLayout.presentation
        switch model.statusIconStyle {
        case .arrows:
            statusItem.length = 30
            button.title = ""; button.image = defaultStatusImage
        case .code:
            statusItem.length = NSStatusItem.variableLength
            button.image = nil; button.title = layout.code
            button.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        case .flag:
            statusItem.length = 30
            button.image = nil; button.title = layout.flag
            button.font = .systemFont(ofSize: 17)
        }
        button.setAccessibilityLabel("LSwitcher · \(layout.code)")
        button.toolTip = model.ready ? "LSwitcher · \(layout.code) · Shift × 2" : "LSwitcher · \(layout.code) · Проверьте разрешения"
    }
    @objc private func layoutChanged() { refreshMenu(); model.focusHint.refresh() }
    private func recreateStatusItem() {
        let menu = statusItem?.menu
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        statusItem.autosaveName = "LSwitcher.StatusItem"
        statusItem.isVisible = true
        statusItem.menu = menu
        statusGeneration += 1
        refreshMenu()
    }
    @objc private func willSleep() {
        recoveryTask?.cancel(); recoveryTask = nil
        model.suspendInput()
    }
    @objc private func didWake() {
        recoveryTask?.cancel()
        model.resumeInput()
        recreateStatusItem()
        recoveryTask = Task { @MainActor [weak self] in
            for (index, delay) in [0.5, 1.5, 4.0].enumerated() {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, !self.model.sessionSuspended else { return }
                self.model.checkHealth()
                AccessibilityFocus.prepare(NSWorkspace.shared.frontmostApplication)
                if index == 1 { self.recreateStatusItem() }
                else { self.refreshMenu() }
            }
        }
    }
    @objc private func screenChanged() { if !model.sessionSuspended { recreateStatusItem() } }
    @objc private func systemAppLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.systemuiserver" else { return }
        recreateStatusItem()
    }
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
