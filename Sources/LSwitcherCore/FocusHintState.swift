/// Tracks only focus and typing, never characters or field contents.
public struct FocusHintState {
    private var typed = false
    private var pendingTyping = false
    public init() {}
    public mutating func reset() { typed = false; pendingTyping = false }
    public mutating func didType() { typed = true; pendingTyping = true }
    public mutating func shouldShow(focusChanged: Bool) -> Bool {
        if focusChanged { typed = pendingTyping }
        pendingTyping = false
        return !typed
    }
}
