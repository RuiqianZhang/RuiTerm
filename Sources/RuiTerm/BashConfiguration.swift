import Foundation
import LanguageSupport
import RegexBuilder

extension LanguageConfiguration {
    public static func bash(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        let numberRegex = Regex {
            Optionally("-")
            OneOrMore(.digit)
            Optionally {
                "."
                OneOrMore(.digit)
            }
        }
        
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
                    .anyOf("_")
                )
            }
        }
        
        let bashReservedIdentifiers = [
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "select",
            "while", "until", "do", "done", "in", "function", "time", "coproc",
            "return", "export", "alias", "echo", "source", "shopt", "set", "unset",
            "local", "readonly", "declare", "typeset", "read", "printf"
        ]
        
        let bashReservedOperators = [
            "=", "+", "-", "*", "/", ">", "<", ">>", "<<", "|", "&", "!", "[", "]", "[[", "]]", ";", "&&", "||"
        ]
        
        return LanguageConfiguration(
            name: "Bash",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            caseInsensitiveReservedIdentifiers: false,
            stringRegex: #/(?:"(?:\\.|[^\\"])*")|(?:'[^']*')/#,
            characterRegex: nil,
            numberRegex: numberRegex,
            singleLineComment: "#",
            nestedComment: nil,
            identifierRegex: identifierRegex,
            operatorRegex: nil,
            reservedIdentifiers: bashReservedIdentifiers,
            reservedOperators: bashReservedOperators,
            languageService: languageService
        )
    }
}
