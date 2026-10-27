import AppKit
@preconcurrency import ApplicationServices
import Combine
import UniformTypeIdentifiers
import LSwitcherCore
import Carbon

@MainActor
final class AppModel: ObservableObject {
    let engine = KeyboardEngine()
    let loginLaunch = LoginLaunch()
    lazy var focusHint = FocusLayoutHint()
    private let preferences: Preferences
    @Published var page = SettingsPage.general
    @Published var testing = false
    @Published var testResults = ""
    @Published var testEditorID = "com.apple.TextEdit"
    @Published var enabled: Bool
    @Published var automatic: Bool
    @Published var statusIconStyle: StatusIconStyle
    @Published var showLayoutHint: Bool
    @Published var shiftMode: String
    @Published var neverCorrect: String
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
    @Published var inputTarget = "—"
    @Published private(set) var operationStatus: OperationStatus = .fieldUnknown
    private var timer: Timer?
    var changed: (() -> Void)?
    var ready: Bool { accessibility && listening && posting && running && !sessionSuspended && !secureInput }

    init(preferences: Preferences = .shared, startInput: Bool = true) {
        self.preferences = preferences
        enabled = preferences.enabled
        automatic = preferences.automatic
        statusIconStyle = preferences.statusIconStyle
        showLayoutHint = preferences.showLayoutHint
        shiftMode = preferences.shiftMode
        neverCorrect = preferences.neverCorrect
        _ = LayoutConverter.prepareLexicon()
        loadExclusions()
        guard startInput else { return }
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
        inputTarget = engine.inputTarget
        refreshOperationStatus()
        focusHint.setAllowed(enabled && showLayoutHint && ready)
        changed?()
    }
    private func refreshOperationStatus() {
        var field: FieldAvailability = .unknown
        var appName = "приложение", excluded = false, protectedApp = false
        var targetID: String?
        if enabled, ready, let app = AccessibilityFocus.keyboardApplication(timeout: 0.04),
           let identifier = app.bundleIdentifier {
            targetID = identifier
            if identifier != Bundle.main.bundleIdentifier {
                appName = app.localizedName ?? identifier
                protectedApp = InputProtection.protectsApplication(identifier)
                excluded = preferences.excludes(identifier)
                if !protectedApp { field = AccessibilityFocus.availability(app: app) }
            }
        }
        engine.observeExclusionContext(applicationID: targetID, enabled: enabled,
            secureInput: secureInput, suspended: sessionSuspended)
        operationStatus = .resolve(enabled: enabled, suspended: sessionSuspended,
            permissions: accessibility && listening && posting, secureInput: secureInput,
            running: running, protectedApplication: protectedApp, excluded: excluded,
            applicationName: appName, field: field, automatic: automatic)
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
        enabled = value; preferences.enabled = value; engine.reset(); refresh()
    }
    func setStatusIconStyle(_ value: StatusIconStyle) {
        statusIconStyle = value; preferences.statusIconStyle = value; changed?()
    }
    func setShowLayoutHint(_ value: Bool) {
        showLayoutHint = value; preferences.showLayoutHint = value; refresh()
    }
    func setAutomatic(_ value: Bool) {
        automatic = value; preferences.automatic = value; engine.reset(); refresh()
    }
    func setShiftMode(_ value: String) {
        shiftMode = value; preferences.shiftMode = value; engine.reset()
    }
    func setNeverCorrect(_ value: String) {
        neverCorrect = String(value.prefix(100_000))
        preferences.neverCorrect = neverCorrect
        engine.reset()
    }
    @discardableResult
    func addPersonalWord(_ word: String) -> PersonalWords.Addition {
        let result = PersonalWords.adding(word, to: neverCorrect)
        if case .added(let updated) = result { setNeverCorrect(updated) }
        return result
    }
    func loadExclusions() {
        excludedIDs = Array(Set(preferences.exclusions.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
    func removeExclusion(_ identifier: String) {
        setExcluded(identifier, excluded: false)
    }
    @discardableResult
    func setExcluded(_ identifier: String, excluded: Bool) -> Bool {
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !identifier.contains(where: { $0.isWhitespace || $0.isNewline }),
              !identifier.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return false }
        // Read the stored list as well: diagnostics/tests can change preferences directly.
        loadExclusions()
        var identifiers = Set(excludedIDs)
        if excluded { identifiers.insert(identifier) } else { identifiers.remove(identifier) }
        excludedIDs = identifiers.sorted()
        preferences.exclusions = excludedIDs.joined(separator: "\n")
        engine.reset()
        refreshOperationStatus()
        changed?()
        return true
    }
    func addExclusion() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Добавить"
        panel.message = "В этом приложении останется только ручное исправление по двойному Shift."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        setExcluded(id, excluded: true)
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
