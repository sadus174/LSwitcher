import Foundation

/// A single replacement for a search field whose completion can change on each key.
/// Offsets are UTF-16, matching Accessibility. No text is retained outside the edit.
public struct SearchFieldEdit {
    public let text: String
    public let caret: Int
    public let replacement: String

    private static func bounds(_ text: String, _ selection: NSRange) -> Range<String.Index>? {
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= text.utf16.count,
              selection.length <= text.utf16.count - selection.location else { return nil }
        return Range(selection, in: text)
    }

    private static func replacing(_ text: String, range: Range<String.Index>, with replacement: String) -> SearchFieldEdit {
        let caret = text[..<range.lowerBound].utf16.count + replacement.utf16.count
        return SearchFieldEdit(text: text.replacingCharacters(in: range, with: replacement), caret: caret, replacement: replacement)
    }

    public static func manual(text: String, selection: NSRange, typedWord: String) -> SearchFieldEdit? {
        guard let selected = bounds(text, selection) else { return nil }
        // A selected tail immediately after the observed word is an inline completion.
        // Mouse/navigation/Command actions clear typedWord before manual selections.
        if selection.length > 0 {
            if !typedWord.isEmpty, selected.upperBound == text.endIndex,
               let edit = suffix(text: text, selection: selection, original: typedWord,
                                 replacement: LayoutConverter.convert(typedWord)) { return edit }
            return replacing(text, range: selected, with: LayoutConverter.convert(String(text[selected])))
        }
        guard let context = WordContext.beforeCursor(in: text, utf16Offset: selection.location) else { return nil }
        return suffix(text: text, selection: selection, original: context.word + context.suffix,
                      replacement: LayoutConverter.convert(context.word) + context.suffix)
    }

    /// Replace only a verified suffix before the caret, dropping selected completion.
    public static func suffix(text: String, selection: NSRange, original: String, replacement: String) -> SearchFieldEdit? {
        guard !original.isEmpty, let selected = bounds(text, selection),
              selection.location >= original.utf16.count,
              let range = bounds(text, NSRange(location: selection.location - original.utf16.count,
                                               length: original.utf16.count + selection.length)),
              text[range.lowerBound..<selected.lowerBound].lowercased() == original.lowercased() else { return nil }
        return replacing(text, range: range, with: replacement)
    }
}
