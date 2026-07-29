enum InsertionContext {
    case unavailable
    case documentStart
    case selection
    case caret(previous: Character)
}

struct InsertionBoundaryPolicy {
    func prepare(_ semanticText: String, context: InsertionContext) -> String {
        guard
            let firstCharacter = semanticText.first,
            beginsWordLikeText(firstCharacter),
            case let .caret(previousCharacter) = context,
            requiresBoundaryAfter(previousCharacter)
        else {
            return semanticText
        }

        return " " + semanticText
    }

    private func beginsWordLikeText(_ character: Character) -> Bool {
        character.isLetter
            || character.isNumber
            || "\"'“‘([{".contains(character)
    }

    private func requiresBoundaryAfter(_ character: Character) -> Bool {
        character.isLetter
            || character.isNumber
            || ".?!,:;)]}\"'”’".contains(character)
    }
}
