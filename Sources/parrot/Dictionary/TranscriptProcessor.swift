import Foundation

struct TranscriptProcessor {
    func process(_ rawText: String, using dictionary: PersonalDictionary) -> String {
        var text = rawText
        text = removeFillers(from: text, words: dictionary.fillerWords)
        text = applyReplacements(to: text, replacements: dictionary.replacements)
        text = normalizeTerms(in: text, terms: dictionary.terms)
        return repairWhitespace(in: text)
    }

    private func removeFillers(from text: String, words: [String]) -> String {
        var result = text
        for word in words.sorted(by: { $0.count > $1.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: word)
            let pattern =
                #"(?:,[\t ]*)?(?<![\p{L}\p{N}])"# + escaped
                + #"(?![\p{L}\p{N}])(?:[\t ]*[,.;:!?])?"#
            result = replacingMatches(
                in: result,
                pattern: pattern,
                options: [.caseInsensitive],
                template: " "
            )
        }
        return result
    }

    private func applyReplacements(
        to text: String,
        replacements: [DictionaryReplacement]
    ) -> String {
        let ordered = replacements
            .flatMap { replacement in
                replacement.variants.map {
                    (variant: $0, canonical: replacement.canonical)
                }
            }
            .sorted {
                if $0.variant.count == $1.variant.count {
                    return $0.variant.localizedCaseInsensitiveCompare($1.variant) == .orderedAscending
                }
                return $0.variant.count > $1.variant.count
            }

        var result = text
        for item in ordered {
            result = replaceBounded(
                item.variant,
                with: item.canonical,
                in: result
            )
        }
        return result
    }

    private func normalizeTerms(in text: String, terms: [String]) -> String {
        var result = text
        for term in terms.sorted(by: {
            if $0.count == $1.count {
                return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            return $0.count > $1.count
        }) {
            result = replaceBounded(term, with: term, in: result)
        }
        return result
    }

    private func replaceBounded(
        _ match: String,
        with replacement: String,
        in text: String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: match)
        let pattern =
            #"(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#
        return replacingMatches(
            in: text,
            pattern: pattern,
            options: [.caseInsensitive],
            template: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    private func repairWhitespace(in text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
        result = replacingMatches(
            in: result,
            pattern: #"[\t ]+"#,
            template: " "
        )
        result = replacingMatches(
            in: result,
            pattern: #" *\n *"#,
            template: "\n"
        )
        result = replacingMatches(
            in: result,
            pattern: #" +([,!?;:]|\.(?![\p{L}\p{N}]))"#,
            template: "$1"
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacingMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: options
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
    }
}
