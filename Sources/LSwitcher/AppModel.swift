import AppKit
@preconcurrency import ApplicationServices
import Combine
import UniformTypeIdentifiers
import LSwitcherCore

@MainActor
final class AppModel: ObservableObject {
    let engine = KeyboardEngine()
    @Published var page = SettingsPage.general
    @Published var testing = false
    @Published var testResults = ""
    @Published var enabled = Preferences.shared.enabled
    @Published var automatic = Preferences.shared.automatic
    @Published var shiftMode = Preferences.shared.shiftMode
    @Published var excludedIDs: [String] = []
    @Published var accessibility = false
    @Published var listening = false
    @Published var posting = false
    @Published var running = false
    @Published var events = 0
    @Published var shiftEvents = 0
    @Published var manualCount = 0
    @Published var autoCount = 0
    @Published var diagnostic = "Ожидание ввода"
    private var timer: Timer?
    var changed: (() -> Void)?
    var ready: Bool { accessibility && posting && running }

    init() {
        _ = LayoutConverter.prepareLexicon()
        loadExclusions()
        engine.statusChanged = { [weak self] in self?.refresh() }
        engine.start()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        listening = CGPreflightListenEventAccess()
        posting = CGPreflightPostEventAccess()
        running = engine.running
        events = engine.eventsReceived
        shiftEvents = engine.shiftEvents
        manualCount = engine.manualCorrections
        autoCount = engine.automaticCorrections
        diagnostic = engine.diagnostic
        changed?()
    }
    func retry() { engine.start(); refresh() }
    func setEnabled(_ value: Bool) {
        enabled = value; Preferences.shared.enabled = value; engine.reset(); changed?()
    }
    func setAutomatic(_ value: Bool) {
        automatic = value; Preferences.shared.automatic = value; engine.reset(); changed?()
    }
    func setShiftMode(_ value: String) {
        shiftMode = value; Preferences.shared.shiftMode = value; engine.reset()
    }
    private func loadExclusions() {
        excludedIDs = Array(Set(Preferences.shared.exclusions.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
    func removeExclusion(_ identifier: String) {
        excludedIDs.removeAll { $0 == identifier }; saveExclusions()
    }
    private func saveExclusions() {
        Preferences.shared.exclusions = excludedIDs.joined(separator: "\n"); engine.reset()
    }
    func addExclusion() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Добавить"
        panel.message = "В этом приложении останется только ручное исправление по двойному Shift."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !excludedIDs.contains(id) { excludedIDs.append(id); excludedIDs.sort(); saveExclusions() }
    }
    func appInfo(_ identifier: String) -> (String, NSImage) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                    NSWorkspace.shared.icon(forFile: url.path))
        }
        let name = ["com.apple.Terminal": "Терминал", "com.googlecode.iterm2": "iTerm",
                    "com.agilebits.onepassword7": "1Password 7", "com.1password.1password": "1Password"][identifier]
            ?? identifier
        return (name, NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!)
    }
    func openAccess(_ monitoring: Bool = false) {
        if monitoring { CGRequestListenEventAccess() }
        else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            CGRequestPostEventAccess()
        }
        let section = monitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)")!)
    }
}
