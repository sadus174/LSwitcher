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
    public static func validWord(_ word: String) -> Bool {
        !word.isEmpty && word.count <= 80 && !word.contains(where: \.isWhitespace)
            && !word.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    public static func normalized(_ text: String) -> Set<String> {
        var words = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
            if validWord(word) { words.insert(word) }
            if words.count == 5000 { break }
        }
        return words
    }
    public static func contains(_ word: String, in words: Set<String>) -> Bool {
        words.contains(word.precomposedStringWithCanonicalMapping.lowercased())
    }
    public enum Addition: Equatable {
        case added(String), alreadyPresent, invalidWord, limitReached
    }
    public static func adding(_ word: String, to text: String) -> Addition {
        let word = word.precomposedStringWithCanonicalMapping.lowercased()
        guard validWord(word) else { return .invalidWord }
        let words = normalized(text)
        if words.contains(word) { return .alreadyPresent }
        guard words.count < 5000 else { return .limitReached }
        let updated = text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + word
        guard updated.count <= 100_000 else { return .limitReached }
        return .added(updated)
    }
}
