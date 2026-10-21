import AppKit
@preconcurrency import ApplicationServices
import Combine
import UniformTypeIdentifiers
import LSwitcherCore
import Carbon

@MainActor
final class AppModel: ObservableObject {
    let engine = KeyboardEngine()
    let focusHint = FocusLayoutHint()
    @Published var page = SettingsPage.general
    @Published var testing = false
    @Published var testResults = ""
    @Published var testEditorID = "com.apple.TextEdit"
    @Published var enabled = Preferences.shared.enabled
    @Published var automatic = Preferences.shared.automatic
    @Published var statusIconStyle = Preferences.shared.statusIconStyle
    @Published var showLayoutHint = Preferences.shared.showLayoutHint
    @Published var shiftMode = Preferences.shared.shiftMode
    @Published var neverCorrect = Preferences.shared.neverCorrect
    @Published var excludedIDs: [String] = []
    @Published var accessibility = false
    @Published var listening = false
    @Published var posting = false
    @Published var running = false
    @Published var secureInput = false
    @Published private(set) var sessionSuspended = false
    @Published var handlerGeneration = 0
    @Published var events = 0
    @Published var shiftEvents = 0
    @Published var manualCount = 0
    @Published var autoCount = 0
    @Published var diagnostic = "Ожидание ввода"
    private var timer: Timer?
    var changed: (() -> Void)?
    var ready: Bool { accessibility && listening && posting && running && !sessionSuspended && !secureInput }

    init() {
        _ = LayoutConverter.prepareLexicon()
        loadExclusions()
        engine.statusChanged = { [weak self] in self?.refresh() }
        engine.typingObserved = { [weak self] in self?.focusHint.didType() }
        engine.start()
        refresh()
        let healthTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
        timer = healthTimer
        RunLoop.main.add(healthTimer, forMode: .common)
    }

    func refresh() {
        secureInput = IsSecureEventInputEnabled()
        handlerGeneration = engine.generation
        accessibility = AXIsProcessTrusted()
        listening = CGPreflightListenEventAccess()
        posting = CGPreflightPostEventAccess()
        running = engine.running
        events = engine.eventsReceived
        shiftEvents = engine.shiftEvents
        manualCount = engine.manualCorrections
        autoCount = engine.automaticCorrections
        diagnostic = engine.diagnostic
        focusHint.setAllowed(enabled && showLayoutHint && ready)
        changed?()
    }
    func checkHealth() {
        if !sessionSuspended, AXIsProcessTrusted(), CGPreflightListenEventAccess(), CGPreflightPostEventAccess(), !IsSecureEventInputEnabled() {
            engine.repairIfNeeded()
        }
        refresh()
    }
    func suspendInput() {
        sessionSuspended = true; engine.suspend(); focusHint.setAllowed(false); refresh()
    }
    func resumeInput() {
        sessionSuspended = false
        AccessibilityFocus.resetPreparation()
        engine.rebuild(); focusHint.reset()
        AccessibilityFocus.prepare(NSWorkspace.shared.frontmostApplication)
        refresh()
    }
    func retry() { guard !sessionSuspended else { return }; engine.rebuild(); refresh() }
    func setEnabled(_ value: Bool) {
        enabled = value; Preferences.shared.enabled = value; engine.reset(); refresh()
    }
    func setStatusIconStyle(_ value: StatusIconStyle) {
        statusIconStyle = value; Preferences.shared.statusIconStyle = value; changed?()
    }
    func setShowLayoutHint(_ value: Bool) {
        showLayoutHint = value; Preferences.shared.showLayoutHint = value; refresh()
    }
    func setAutomatic(_ value: Bool) {
        automatic = value; Preferences.shared.automatic = value; engine.reset(); changed?()
    }
    func setShiftMode(_ value: String) {
        shiftMode = value; Preferences.shared.shiftMode = value; engine.reset()
    }
    func setNeverCorrect(_ value: String) {
        neverCorrect = String(value.prefix(100_000))
        Preferences.shared.neverCorrect = neverCorrect
        engine.reset()
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
