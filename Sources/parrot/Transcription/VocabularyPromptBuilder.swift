import Foundation

enum VocabularyPromptBuilder {
    static func tokens(
        for terms: [String],
        maximumCount: Int = 224,
        encode: (String) -> [Int]
    ) -> [Int]? {
        var seen = Set<String>()
        let uniqueTerms = terms.compactMap { term -> String? in
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            guard seen.insert(clean.lowercased()).inserted else { return nil }
            return clean
        }
        guard !uniqueTerms.isEmpty else { return nil }
        let encoded = encode(uniqueTerms.joined(separator: ", "))
        guard !encoded.isEmpty else { return nil }
        return Array(encoded.suffix(max(0, maximumCount)))
    }
}
