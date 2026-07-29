import Foundation

struct CorrectionProposal: Equatable {
    let original: String
    let corrected: String
}

enum CorrectionDiff {
    private struct Token {
        let text: String
        let range: NSRange
    }

    static func proposal(
        original: String,
        corrected: String
    ) -> CorrectionProposal? {
        guard original != corrected else { return nil }
        guard !original.contains("\n"), !corrected.contains("\n") else { return nil }

        let originalTokens = tokens(in: original)
        let correctedTokens = tokens(in: corrected)
        guard !originalTokens.isEmpty, !correctedTokens.isEmpty else { return nil }

        var prefixCount = 0
        while prefixCount < min(originalTokens.count, correctedTokens.count),
              originalTokens[prefixCount].text == correctedTokens[prefixCount].text {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < originalTokens.count - prefixCount,
              suffixCount < correctedTokens.count - prefixCount,
              originalTokens[originalTokens.count - suffixCount - 1].text
                == correctedTokens[correctedTokens.count - suffixCount - 1].text {
            suffixCount += 1
        }

        let originalEnd = originalTokens.count - suffixCount
        let correctedEnd = correctedTokens.count - suffixCount
        guard prefixCount < originalEnd, prefixCount < correctedEnd else {
            return nil
        }

        let originalMiddle = substring(
            original,
            from: originalTokens[prefixCount].range,
            through: originalTokens[originalEnd - 1].range
        )
        let correctedMiddle = substring(
            corrected,
            from: correctedTokens[prefixCount].range,
            through: correctedTokens[correctedEnd - 1].range
        )
        let cleanOriginal = originalMiddle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCorrected = correctedMiddle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanOriginal.isEmpty, !cleanCorrected.isEmpty else { return nil }
        guard cleanOriginal.count <= 80, cleanCorrected.count <= 80 else { return nil }
        guard wordCount(cleanOriginal) <= 8, wordCount(cleanCorrected) <= 8 else {
            return nil
        }

        let originalCharacters = Array(cleanOriginal.lowercased())
        let correctedCharacters = Array(cleanCorrected.lowercased())
        let distance = levenshteinDistance(
            originalCharacters,
            correctedCharacters
        )
        let longerCount = max(originalCharacters.count, correctedCharacters.count)
        let maximumDistance = max(3, Int(ceil(Double(longerCount) * 0.45)))
        guard distance <= maximumDistance else { return nil }

        return CorrectionProposal(
            original: cleanOriginal,
            corrected: cleanCorrected
        )
    }

    private static func tokens(in text: String) -> [Token] {
        let pattern = #"\.?[\p{L}\p{N}]+(?:[._'’-][\p{L}\p{N}]+)*"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        return expression.matches(in: text, range: range).map {
            Token(text: nsText.substring(with: $0.range), range: $0.range)
        }
    }

    private static func substring(
        _ text: String,
        from first: NSRange,
        through last: NSRange
    ) -> String {
        let range = NSRange(
            location: first.location,
            length: NSMaxRange(last) - first.location
        )
        return (text as NSString).substring(with: range)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func levenshteinDistance(
        _ left: [Character],
        _ right: [Character]
    ) -> Int {
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitution = previous[rightIndex]
                    + (leftCharacter == rightCharacter ? 0 : 1)
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    substitution
                )
            }
            previous = current
        }
        return previous[right.count]
    }
}
