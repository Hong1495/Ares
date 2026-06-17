import Foundation

nonisolated enum SudoersEscaper {
    private static let wordEscapedCharacters = Set("!=:,()\\")
    private static let commandEscapedCharacters = Set(" \t\"'\\")

    static func user(_ value: String) -> String {
        value.map { character -> String in
            if wordEscapedCharacters.contains(character) {
                return "\\\(character)"
            }
            return String(character)
        }.joined()
    }

    static func commandPath(_ value: String) -> String {
        value.map { character -> String in
            if commandEscapedCharacters.contains(character) {
                return "\\\(character)"
            }
            return String(character)
        }.joined()
    }
}
