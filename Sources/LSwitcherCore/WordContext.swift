import Foundation

public struct WordContext: Equatable {
    public let word: String
    public let suffix: String

    public static func beforeCursor(in text: String, utf16Offset: Int) -> WordContext? {
        guard utf16Offset >= 0, utf16Offset <= text.utf16.count,
              let position = String.Index(utf16Offset: utf16Offset, in: text).samePosition(in: text) else { return nil }
        var prefix = String(text[..<position])
        var suffix = ""
        while let last = prefix.last, last == " " || last == "\t" {
            suffix.insert(prefix.removeLast(), at: suffix.startIndex)
        }
        var candidate = ""
        while let last = prefix.last, last.isLetter || "[];',`.".contains(last) {
            candidate.insert(prefix.removeLast(), at: candidate.startIndex)
        }
        return candidate.isEmpty ? nil : WordContext(word: candidate, suffix: suffix)
    }
}
