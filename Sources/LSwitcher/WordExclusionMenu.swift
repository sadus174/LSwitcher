import AppKit
import LSwitcherCore

@MainActor
final class WordExclusionMenu: NSObject, NSMenuItemValidation {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let model: AppModel
    private var candidateID: UUID?

    init(model: AppModel) {
        self.model = model
        super.init()
        item.target = self; item.action = #selector(apply)
        invalidate()
    }
    func prepare() {
        guard let candidate = model.engine.exclusionCandidate() else { invalidate(); return }
        candidateID = candidate.id
        item.title = "Больше не исправлять «\(candidate.word)»"
        item.isHidden = false; item.isEnabled = true
    }
    func refreshAvailability() {
        if !validateMenuItem(item) { invalidate() }
    }
    private func invalidate() {
        candidateID = nil
        item.title = ""; item.isHidden = true; item.isEnabled = false
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let candidateID, let candidate = model.engine.exclusionCandidate() else { return false }
        return candidate.id == candidateID
    }
    @objc private func apply() {
        model.refresh()
        guard validateMenuItem(item), let candidate = model.engine.exclusionCandidate() else { invalidate(); return }
        let result = model.addPersonalWord(candidate.word)
        model.engine.clearExclusionCandidate()
        invalidate()
        let message: String?
        switch result {
        case .added, .alreadyPresent: message = nil
        case .invalidWord: message = "Это слово не соответствует ограничениям личных исключений."
        case .limitReached: message = "Достигнут лимит списка исключений. Удалите ненужные записи в настройках."
        }
        if let message {
            let alert = NSAlert(); alert.messageText = "Слово не добавлено"; alert.informativeText = message
            alert.runModal()
        }
    }
}
