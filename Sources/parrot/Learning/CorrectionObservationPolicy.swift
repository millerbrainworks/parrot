import Foundation

struct CorrectionObservationPolicy {
    let timeout: TimeInterval

    func selectedRangeForPreparation(
        access: AccessibilityTextAccess,
        readSelectedRange: () -> CFRange?
    ) -> CFRange? {
        guard AccessibilityTextAccessResolver.allowsTextAccess(access) else {
            return nil
        }
        guard let selection = readSelectedRange() else {
            return nil
        }
        return CorrectionObservationRangePolicy.validatedSelection(selection)
    }

    func selectedRangeForPoll(
        elapsed: TimeInterval,
        sameElement: Bool,
        access: AccessibilityTextAccess,
        readSelectedRange: () -> CFRange?
    ) -> CFRange? {
        guard
            elapsed <= timeout,
            sameElement,
            AccessibilityTextAccessResolver.allowsTextAccess(access)
        else {
            return nil
        }
        guard let selection = readSelectedRange() else {
            return nil
        }
        return CorrectionObservationRangePolicy.validatedSelection(selection)
    }
}

enum CorrectionObservationReadPlan: Equatable {
    case wait
    case cancel
    case read(location: Int, length: Int)
}

enum CorrectionObservationRangePolicy {
    static func validatedSelection(_ range: CFRange) -> CFRange? {
        guard range.location >= 0, range.length >= 0 else {
            return nil
        }
        let (_, overflow) = range.location.addingReportingOverflow(
            range.length
        )
        guard !overflow else {
            return nil
        }
        return range
    }

    static func readPlan(
        selection: CFRange,
        insertionStart: Int,
        originalLength: Int,
        allowance: Int = 64
    ) -> CorrectionObservationReadPlan {
        guard
            validatedSelection(selection) != nil,
            insertionStart >= 0,
            originalLength >= 0,
            allowance >= 0
        else {
            return .cancel
        }

        let (caret, caretOverflow) = selection.location
            .addingReportingOverflow(selection.length)
        guard !caretOverflow else {
            return .cancel
        }

        let (allowedLength, lengthOverflow) = originalLength
            .addingReportingOverflow(allowance)
        guard !lengthOverflow else {
            return .cancel
        }

        let (allowedEnd, endOverflow) = insertionStart
            .addingReportingOverflow(allowedLength)
        guard !endOverflow else {
            return .cancel
        }

        guard caret >= insertionStart else {
            return .wait
        }
        guard caret <= allowedEnd else {
            return .cancel
        }
        return .read(
            location: insertionStart,
            length: caret - insertionStart
        )
    }
}

enum CorrectionPrefixResolver {
    static func proposal(
        original: String,
        observedPrefix: String
    ) -> CorrectionProposal? {
        guard original != observedPrefix else { return nil }
        guard !observedPrefix.hasPrefix(original) else { return nil }

        let observedLength = observedPrefix.utf16.count
        var proposals: [CorrectionProposal] = []
        for index in candidateBoundaries(in: original) {
            let prefix = String(original[..<index])
            guard abs(prefix.utf16.count - observedLength) <= 64 else {
                continue
            }
            guard let candidate = CorrectionDiff.proposal(
                original: prefix,
                corrected: observedPrefix
            ) else {
                continue
            }
            if !proposals.contains(candidate) {
                proposals.append(candidate)
            }
        }
        guard !proposals.isEmpty else { return nil }
        let ranked = proposals.sorted {
            proposalScore($0) < proposalScore($1)
        }
        if ranked.count > 1,
           proposalScore(ranked[0]) == proposalScore(ranked[1]) {
            return nil
        }
        return ranked[0]
    }

    private static func candidateBoundaries(in text: String) -> [String.Index] {
        var boundaries: [String.Index] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]
            let nextIsWord = next < text.endIndex && isWordCharacter(text[next])
            if isWordCharacter(character), !nextIsWord {
                boundaries.append(next)
            }
            index = next
        }
        if boundaries.last != text.endIndex {
            boundaries.append(text.endIndex)
        }
        return boundaries
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || $0 == "_"
                || $0 == "."
                || $0 == "-"
                || $0 == "'"
                || $0 == "’"
        }
    }

    private static func proposalScore(_ proposal: CorrectionProposal) -> Int {
        let wordCount = proposal.original.split(whereSeparator: \.isWhitespace).count
            + proposal.corrected.split(whereSeparator: \.isWhitespace).count
        return wordCount * 100 + proposal.original.count + proposal.corrected.count
    }
}
