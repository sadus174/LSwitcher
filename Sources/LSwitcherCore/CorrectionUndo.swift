import Foundation

/// One short-lived correction, in memory only. Never a history of typed text.
public struct CorrectionUndo {
    public let original: String
    public let replacement: String
    public let delimiter: String
    public let caret: Int
    private let created: Double
    public init(original: String, replacement: String, delimiter: String, caret: Int, time: Double) {
        self.original = original; self.replacement = replacement
        self.delimiter = delimiter; self.caret = caret; created = time
    }
    public func matches(text: String, caret: Int, selectionLength: Int, time: Double) -> Bool {
        guard time >= created, time - created <= 5, selectionLength == 0, caret == self.caret,
              caret >= 0, caret <= text.utf16.count,
              let end = String.Index(utf16Offset: caret, in: text).samePosition(in: text) else { return false }
        return text[..<end].suffix((replacement + delimiter).count).lowercased() == (replacement + delimiter).lowercased()
    }
}

public enum PersonalWords {
    public static func normalized(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
        }.filter { !$0.isEmpty && $0.count <= 80 && !$0.contains(where: \.isWhitespace) }.prefix(5000))
    }
    public static func contains(_ word: String, in words: Set<String>) -> Bool {
        words.contains(word.precomposedStringWithCanonicalMapping.lowercased())
    }
}
