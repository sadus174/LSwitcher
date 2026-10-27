import AppKit

/// A menu session owns one target; selection must never re-read keyboard focus.
@MainActor
final class AppExclusionMenu: NSObject, NSMenuItemValidation {
    let item = NSMenuItem(title: "Нет приложения для исключения", action: nil, keyEquivalent: "")
    private let model: AppModel
    private let resolveApplication: (pid_t) -> NSRunningApplication?
    private var application: NSRunningApplication?
    private var identifier: String?
    private var shouldExclude = false

    init(model: AppModel, resolveApplication: @escaping (pid_t) -> NSRunningApplication? = { NSRunningApplication(processIdentifier: $0) }) {
        self.model = model
        self.resolveApplication = resolveApplication
        super.init()
        item.target = self
        item.action = #selector(apply)
        item.isEnabled = false
    }

    func prepare(application: NSRunningApplication?) {
        self.application = nil
        identifier = nil
        item.title = "Нет приложения для исключения"
        item.isEnabled = false
        guard let application, !application.isTerminated, application.processIdentifier > 0,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let identifier = application.bundleIdentifier, !identifier.isEmpty,
              identifier != Bundle.main.bundleIdentifier else { return }
        self.application = application
        self.identifier = identifier
        model.loadExclusions()
        shouldExclude = !model.excludedIDs.contains(identifier)
        let name = String((application.localizedName ?? identifier)
            .components(separatedBy: .controlCharacters).joined(separator: " ").prefix(80))
        item.title = shouldExclude ? "Не исправлять автоматически в «\(name)»" : "Включить автоисправление в «\(name)»"
        item.isEnabled = true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let application, let identifier, !application.isTerminated,
              let current = resolveApplication(application.processIdentifier) else { return false }
        return current.bundleIdentifier == identifier && current.launchDate == application.launchDate
    }

    @objc private func apply() {
        guard validateMenuItem(item), let identifier else { return }
        model.setExcluded(identifier, excluded: shouldExclude)
    }
}
