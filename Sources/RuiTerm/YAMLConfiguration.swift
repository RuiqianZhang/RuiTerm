import Foundation
import LanguageSupport
import RegexBuilder

extension LanguageConfiguration {
    public static func yaml(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        let numberRegex = Regex {
            Optionally("-")
            OneOrMore(.digit)
            Optionally {
                "."
                OneOrMore(.digit)
            }
        }
        
        let yamlReservedIdentifiers = [
            "true", "false", "null", "yes", "no"
        ]
        
        let identifierRegex = Regex {
            CharacterClass(
                "a"..."z",
                "A"..."Z",
                .anyOf("_")
            )
            ZeroOrMore {
                CharacterClass(
                    "a"..."z",
                    "A"..."Z",
                    "0"..."9",
                    .anyOf("_-")
                )
            }
        }
        
        return LanguageConfiguration(
            name: "YAML",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            caseInsensitiveReservedIdentifiers: true,
            stringRegex: #/(?:"(?:\\.|[^\\"])*")|(?:'[^']*')/#,
            characterRegex: nil,
            numberRegex: numberRegex,
            singleLineComment: "#",
            nestedComment: nil,
            identifierRegex: identifierRegex,
            operatorRegex: #/[:\-|>]/#,
            reservedIdentifiers: yamlReservedIdentifiers,
            reservedOperators: [":", "-"],
            languageService: languageService
        )
    }
}
