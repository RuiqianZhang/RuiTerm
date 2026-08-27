import Foundation
import LanguageSupport
import RegexBuilder

extension LanguageConfiguration {
    public static func json(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        let numberRegex = Regex {
            Optionally("-")
            OneOrMore(.digit)
            Optionally {
                "."
                OneOrMore(.digit)
            }
            Optionally {
                CharacterClass(.anyOf("eE"))
                Optionally(CharacterClass(.anyOf("+-")))
                OneOrMore(.digit)
            }
        }
        
        let jsonReservedIdentifiers = [
            "true", "false", "null"
        ]
        
        return LanguageConfiguration(
            name: "JSON",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            caseInsensitiveReservedIdentifiers: false,
            stringRegex: #/"(?:\\.|[^\\"])*"/#,
            characterRegex: nil,
            numberRegex: numberRegex,
            singleLineComment: nil,
            nestedComment: nil,
            identifierRegex: nil,
            operatorRegex: #/:/#,
            reservedIdentifiers: jsonReservedIdentifiers,
            reservedOperators: [],
            languageService: languageService
        )
    }
}
