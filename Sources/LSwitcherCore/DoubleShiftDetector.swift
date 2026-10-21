/// Recognizes two short, isolated presses. Typing a capital letter must never trigger it.
public struct DoubleShiftDetector {
    private var pressedAt: Double?
    private var releasedAt: Double?
    public init() {}
    public mutating func cancel() { pressedAt = nil; releasedAt = nil }
    public mutating func update(isDown: Bool, time: Double, otherModifiers: Bool = false) -> Bool {
        guard !otherModifiers else { cancel(); return false }
        if isDown {
            if pressedAt == nil { pressedAt = time }
            return false
        }
        guard let start = pressedAt else { return false }
        pressedAt = nil
        guard time >= start, time - start <= 0.3 else { releasedAt = nil; return false }
        if let previous = releasedAt, start >= previous, time - previous <= 0.4 {
            releasedAt = nil
            return true
        }
        releasedAt = time
        return false
    }
}

public enum AutomaticExclusions {
    public static func contains(_ identifier: String, in list: String) -> Bool {
        list.split(whereSeparator: \.isNewline).contains {
            identifier == $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
