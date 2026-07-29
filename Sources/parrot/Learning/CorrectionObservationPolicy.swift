import Foundation

struct CorrectionObservationPolicy {
    let timeout: TimeInterval

    func canObserve(
        elapsed: TimeInterval,
        sameElement: Bool,
        secure: Bool
    ) -> Bool {
        elapsed <= timeout && sameElement && !secure
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
