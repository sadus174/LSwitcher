import Foundation

public enum LayoutConverter {
    private static let latin = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?")
    private static let russian = Array("ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,")
    private static let toRussian = Dictionary(uniqueKeysWithValues: zip(latin, russian))
    private static let toEnglish = Dictionary(uniqueKeysWithValues: zip(russian, latin))

    public static func isRussian(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    public static func convert(_ text: String) -> String {
        let russianCount = text.filter(isRussian).count
        let latinCount = text.filter { $0.isASCII && $0.isLetter }.count
        let mapping = russianCount > latinCount ? toEnglish : toRussian
        return String(text.map { mapping[$0] ?? $0 })
    }

    /// Warm up outside the event-tap callback. Resource failure disables automatic
    /// changes; manual conversion remains available.
    public static func prepareLexicon() -> Bool { CompactLexicon.shared != nil }
    public static var lexiconEntryCount: Int { CompactLexicon.shared?.count ?? 0 }
    public static var lexiconDecodedBytes: Int { CompactLexicon.shared?.decodedBytes ?? 0 }

    public static func automaticReplacement(for word: String) -> String? {
        automaticReplacement(for: word, policy: .production)
    }

    package static func automaticReplacement(for word: String, policy: CorrectionPolicy) -> String? {
        guard word.count >= 3, word.count <= 40,
              !word.dropFirst().contains(where: { $0.isUppercase }) else { return nil }
        let lower = word.precomposedStringWithCanonicalMapping.lowercased()
        let russian = lower.contains(where: isRussian)
        if russian {
            guard lower.unicodeScalars.allSatisfy({ (0x0430...0x044F).contains($0.value) || $0.value == 0x0451 }) else { return nil }
        } else {
            guard lower.utf8.allSatisfy({ (97...122).contains($0) || [91, 93, 59, 39, 44, 96, 46].contains($0) }) else { return nil }
        }
        let key = russian ? convert(lower) : lower
        guard let entry = CompactLexicon.shared?.lookup(Array(key.utf8)) else { return nil }
        let sourceValid = entry.flags & (russian ? 2 : 1) != 0
        let targetEligible = entry.flags & (russian ? 4 : 8) != 0
        let sourceScore = Int(russian ? entry.russian : entry.english)
        let targetScore = Int(russian ? entry.english : entry.russian)
        let minimum = word.count == 3 ? max(policy.minimum, policy.shortThree) :
            word.count == 4 ? max(policy.minimum, policy.shortFour) : policy.minimum
        guard targetEligible, !(policy.protectKnownWords && sourceValid),
              targetScore >= minimum, targetScore - sourceScore >= policy.margin else { return nil }
        return convert(word)
    }
}

package struct CorrectionPolicy: Sendable {
    package let protectKnownWords: Bool
    package let minimum: Int
    package let margin: Int
    package let shortThree: Int
    package let shortFour: Int
    package static let production = CorrectionPolicy(protectKnownWords: true, minimum: 48, margin: 8, shortThree: 85, shortFour: 67)
}
