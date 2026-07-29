import Foundation

struct DictionaryReplacement: Codable, Equatable {
    var canonical: String
    var variants: [String]
}

struct PersonalDictionary: Codable, Equatable {
    var version: Int
    var terms: [String]
    var replacements: [DictionaryReplacement]
    var fillerWords: [String]

    static let starter = PersonalDictionary(
        version: 1,
        terms: starterTerms,
        replacements: [
            .init(canonical: "Arcqtype", variants: ["archetype", "arc type", "ark type"]),
            .init(canonical: "want to", variants: ["wanna"]),
            .init(canonical: ".env", variants: ["env"]),
            .init(canonical: "spec", variants: ["speck"]),
            .init(canonical: "by the way", variants: ["btw"]),
            .init(canonical: "pane", variants: ["pain"]),
            .init(canonical: "TMUX", variants: ["teemux"]),
            .init(canonical: "AT", variants: ["A T"]),
            .init(canonical: "Claude", variants: ["Cloud"]),
            .init(canonical: "OT", variants: ["O T"]),
        ],
        fillerWords: ["um", "uh", "erm", "ah"]
    )

    private static let starterTerms = [
        "Ambra",
        "AmbrasWorkspace",
        "queue",
        "arq anchor scale",
        "BodyPark",
        "ARQ",
        "ARQ Score",
        "a2",
        "now.w",
        "poller",
        "Backbrief",
        "TmUX",
        "env vars",
        "TMUX pane",
        "Adversarially verify, merge, and advance",
        "Wispr Flow",
        "ARCQTYPE-API",
        "SIWA",
        "Dhermi",
        "Sarande",
        "neumorphic",
        "guardrail",
        "guardrailed",
        "cuesYouTube",
        "SSD1",
        "DeepSeek",
        "spint",
        "Termius",
        "Vercel",
        "don",
        "simulator",
        "Cron",
        "execute",
        "spec this out",
        "run the sim",
        "Opus",
        "carvana",
        "coach",
        "sprints",
        "metabase",
        "main",
        ".env",
        "Maestro",
        "don miller",
        "sim",
        "xcode",
        "Arcqtype",
        "as applicable",
        "spec",
        "use subagents",
        "spawn subagents",
        "Codex",
        "spawn",
        "subagents",
        "agents.md",
        "claude.md",
        "seed-report",
        "forth",
        "openAI",
        "seedBAC",
        "MIAU",
        "chaminade",
        "openclaw",
        "MillerBrainworks",
        "claude",
        "Macmini",
        "Idle",
        "Scrapling",
        "Supabase",
        "SafeDose",
        "revenuecat",
        "dcos",
    ]
}

enum PersonalDictionaryValidationError: Error, Equatable {
    case unsupportedVersion(Int)
    case blankTerm
    case duplicateTerm(String)
    case blankCanonical
    case duplicateCanonical(String)
    case emptyVariants(String)
    case blankVariant
    case duplicateVariant(String)
    case blankFiller
    case duplicateFiller(String)
}

extension PersonalDictionary {
    func validated() throws -> PersonalDictionary {
        guard version == 1 else {
            throw PersonalDictionaryValidationError.unsupportedVersion(version)
        }

        var seenTerms = Set<String>()
        for term in terms {
            let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw PersonalDictionaryValidationError.blankTerm
            }
            let key = normalized.lowercased()
            guard seenTerms.insert(key).inserted else {
                throw PersonalDictionaryValidationError.duplicateTerm(term)
            }
        }

        var seenCanonicals = Set<String>()
        var seenVariants = Set<String>()
        for replacement in replacements {
            let canonical = replacement.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty else {
                throw PersonalDictionaryValidationError.blankCanonical
            }
            guard seenCanonicals.insert(canonical.lowercased()).inserted else {
                throw PersonalDictionaryValidationError.duplicateCanonical(replacement.canonical)
            }
            guard !replacement.variants.isEmpty else {
                throw PersonalDictionaryValidationError.emptyVariants(replacement.canonical)
            }
            for variant in replacement.variants {
                let normalized = variant.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    throw PersonalDictionaryValidationError.blankVariant
                }
                let key = normalized.lowercased()
                guard seenVariants.insert(key).inserted else {
                    throw PersonalDictionaryValidationError.duplicateVariant(variant)
                }
            }
        }

        var seenFillers = Set<String>()
        for filler in fillerWords {
            let normalized = filler.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw PersonalDictionaryValidationError.blankFiller
            }
            let key = normalized.lowercased()
            guard seenFillers.insert(key).inserted else {
                throw PersonalDictionaryValidationError.duplicateFiller(filler)
            }
        }

        return self
    }
}
