import Foundation

/// One expiring offer, separate from the five-second text-edit undo state.
public struct UndoExclusionCandidate: Equatable {
    public let id: UUID
    public let word: String
    public let applicationID: String
    private let created: Double

    public init?(word: String, applicationID: String, time: Double) {
        guard PersonalWords.validWord(word), !applicationID.isEmpty, time.isFinite else { return nil }
        id = UUID(); self.word = word; self.applicationID = applicationID; created = time
    }

    public func isValid(at time: Double) -> Bool {
        time.isFinite && time >= created && time - created < 60
    }
}

public struct UndoExclusionState {
    private var candidate: UndoExclusionCandidate?
    public init() {}
    public mutating func offer(word: String, applicationID: String, time: Double) {
        candidate = UndoExclusionCandidate(word: word, applicationID: applicationID, time: time)
    }
    public mutating func current(at time: Double) -> UndoExclusionCandidate? {
        if candidate?.isValid(at: time) != true { candidate = nil }
        return candidate
    }
    public mutating func clear() { candidate = nil }
    public mutating func observe(applicationID: String?, ownApplicationID: String?, enabled: Bool,
                                 secureInput: Bool, suspended: Bool, time: Double) {
        guard enabled, !secureInput, !suspended else { clear(); return }
        guard let current = current(at: time) else { return }
        if applicationID == ownApplicationID, ownApplicationID != nil { return }
        if applicationID != current.applicationID { clear() }
    }
}
