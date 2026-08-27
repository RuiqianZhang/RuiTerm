import Foundation
import LanguageSupport
import RegexBuilder

extension LanguageConfiguration {
    public static func xml(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        let identifierRegex = Regex {
            CharacterClass(
                "a"..."z",
                "A"..."Z",
                "0"..."9",
                .anyOf("_:-")
            )
            ZeroOrMore {
                CharacterClass(
                    "a"..."z",
                    "A"..."Z",
                    "0"..."9",
                    .anyOf("_:-.")
                )
            }
        }
        
        let xmlReservedOperators = [
            "<", ">", "</", "/>", "=", "?", "<?", "?>"
        ]
        
        return LanguageConfiguration(
            name: "XML",
            supportsSquareBrackets: false,
            supportsCurlyBrackets: false,
            caseInsensitiveReservedIdentifiers: false,
            stringRegex: #/(?:"(?:\\.|[^\\"])*")|(?:'[^']*')/#,
            characterRegex: nil,
            numberRegex: nil,
            singleLineComment: nil,
            nestedComment: (open: "<!--", close: "-->"),
            identifierRegex: identifierRegex,
            operatorRegex: #/[<>=\/?]/#,
            reservedIdentifiers: [],
            reservedOperators: xmlReservedOperators,
            languageService: languageService
        )
    }
}
