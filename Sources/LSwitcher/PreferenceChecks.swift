import AppKit
import LSwitcherCore

private enum PreferenceCheckFailure: Error {
    case failed(String)
}

/// Developer checks use a disposable domain and never start the input engine.
@MainActor
func checkExclusionPreferences() throws {
    let suite = "com.lswitcher.checks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { throw PreferenceCheckFailure.failed("suite") }
    defer { defaults.removePersistentDomain(forName: suite); defaults.synchronize() }
    defaults.set(" com.example.first \ncom.example.first\ncom.example.second\n", forKey: "exclusions")
    let model = AppModel(preferences: Preferences(defaults: defaults), startInput: false)
    guard model.excludedIDs == ["com.example.first", "com.example.second"],
          model.setExcluded("com.example.third", excluded: true),
          model.setExcluded("com.example.third", excluded: true),
          model.setExcluded("com.example.first", excluded: false),
          model.excludedIDs == ["com.example.second", "com.example.third"],
          defaults.string(forKey: "exclusions") == "com.example.second\ncom.example.third",
          !model.setExcluded("bad\nidentifier", excluded: true),
          !model.setExcluded("", excluded: true) else {
        throw PreferenceCheckFailure.failed("shared mutation and normalization")
    }
    defaults.synchronize()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    process.arguments = ["--probe-exclusions", suite]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw PreferenceCheckFailure.failed("restart persistence") }
    model.removeExclusion("com.example.third")
    guard model.excludedIDs == ["com.example.second"],
          defaults.string(forKey: "exclusions") == "com.example.second" else {
        throw PreferenceCheckFailure.failed("settings removal")
    }
    guard case .added = model.addPersonalWord("GHBDTN"), model.neverCorrect == "ghbdtn",
          model.addPersonalWord("Ghbdtn") == .alreadyPresent else {
        throw PreferenceCheckFailure.failed("personal word addition")
    }
    let full = (0..<5000).map { "entry\($0)" }.joined(separator: "\n")
    model.setNeverCorrect(full)
    guard model.addPersonalWord("new") == .limitReached, model.neverCorrect == full,
          defaults.string(forKey: "neverCorrect") == full,
          model.addPersonalWord(String(repeating: "x", count: 81)) == .invalidWord else {
        throw PreferenceCheckFailure.failed("personal word limits preserve stored words")
    }
    print("Exclusion preferences: normalization, shared mutation, deduplication, new-process persistence and personal-word limits passed")
}

@MainActor
func probeExclusionPreferences(suite: String) throws {
    guard suite.hasPrefix("com.lswitcher.checks."), let defaults = UserDefaults(suiteName: suite) else {
        throw PreferenceCheckFailure.failed("invalid probe domain")
    }
    let model = AppModel(preferences: Preferences(defaults: defaults), startInput: false)
    guard model.excludedIDs == ["com.example.second", "com.example.third"] else {
        throw PreferenceCheckFailure.failed("fresh process model")
    }
}

@MainActor
func checkExclusionMenu() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let suite = "com.lswitcher.checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite); defaults.synchronize() }
    defaults.set("", forKey: "exclusions")
    let model = AppModel(preferences: Preferences(defaults: defaults), startInput: false)
    var targetStillRunning = true
    let controller = AppExclusionMenu(model: model, resolveApplication: { pid in
        targetStillRunning ? NSRunningApplication(processIdentifier: pid) : nil
    })
    let menu = NSMenu()
    menu.addItem(controller.item)
    guard let target = NSWorkspace.shared.runningApplications.first(where: {
        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated && $0.bundleIdentifier != nil
    }), let identifier = target.bundleIdentifier else { throw PreferenceCheckFailure.failed("no running menu target") }
    controller.prepare(application: target)
    guard controller.validateMenuItem(controller.item), controller.item.title.contains("Не исправлять") else {
        throw PreferenceCheckFailure.failed("menu target")
    }
    // A later focus change cannot affect this action: only the prepared process is used.
    menu.performActionForItem(at: 0)
    guard model.excludedIDs == [identifier] else { throw PreferenceCheckFailure.failed("menu add") }
    controller.prepare(application: target)
    guard controller.item.title.contains("Включить") else { throw PreferenceCheckFailure.failed("inverse action") }
    menu.performActionForItem(at: 0)
    guard model.excludedIDs.isEmpty else { throw PreferenceCheckFailure.failed("menu remove") }
    controller.prepare(application: target)
    targetStillRunning = false
    guard !controller.validateMenuItem(controller.item) else { throw PreferenceCheckFailure.failed("stale target validation") }
    menu.performActionForItem(at: 0)
    guard model.excludedIDs.isEmpty else { throw PreferenceCheckFailure.failed("stale target mutation") }
    for unavailable in [nil, NSRunningApplication.current] as [NSRunningApplication?] {
        controller.prepare(application: unavailable)
        guard !controller.item.isEnabled, !controller.validateMenuItem(controller.item) else {
            throw PreferenceCheckFailure.failed("unavailable menu target")
        }
    }
    print("Exclusion menu: target snapshot, real menu add/remove actions and unavailable/self/stale guards passed")
}
