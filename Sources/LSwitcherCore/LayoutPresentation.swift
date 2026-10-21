public enum StatusIconStyle: String, CaseIterable, Sendable {
    case arrows, code, flag
}

public struct LayoutPresentation: Equatable, Sendable {
    public let code: String
    public let flag: String
    public init(language: String, sourceID: String) {
        let language = language.lowercased()
        if language.hasPrefix("ru") { code = "RU"; flag = "🇷🇺" }
        else if language.hasPrefix("en") {
            code = "EN"; flag = sourceID.lowercased().contains("british") ? "🇬🇧" : "🇺🇸"
        } else {
            let letters = language.prefix(while: { $0.isLetter }).prefix(3)
            code = letters.isEmpty ? "—" : letters.uppercased()
            flag = letters.isEmpty ? "⌨" : code
        }
    }
}
