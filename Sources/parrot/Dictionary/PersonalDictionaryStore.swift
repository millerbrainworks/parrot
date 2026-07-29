import Foundation

struct DictionaryLoadResult {
    let dictionary: PersonalDictionary
    let warning: String?
}

final class PersonalDictionaryStore {
    let rootDirectory: URL
    var fileURL: URL {
        rootDirectory.appendingPathComponent("personal-dictionary.json")
    }

    private let fileManager: FileManager
    private var lastValid: PersonalDictionary?
    private let lock = NSLock()

    init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Parrot"),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func load() throws -> PersonalDictionary {
        lock.lock()
        defer { lock.unlock() }
        return try loadLocked()
    }

    func loadUsingFallback() -> DictionaryLoadResult {
        do {
            return DictionaryLoadResult(dictionary: try load(), warning: nil)
        } catch {
            lock.lock()
            let fallback = lastValid ?? .starter
            lock.unlock()
            return DictionaryLoadResult(
                dictionary: fallback,
                warning: "Personal Dictionary Needs Attention"
            )
        }
    }

    func learn(variant: String, canonical: String) throws {
        let cleanVariant = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCanonical = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanVariant.isEmpty else {
            throw PersonalDictionaryValidationError.blankVariant
        }
        guard !cleanCanonical.isEmpty else {
            throw PersonalDictionaryValidationError.blankCanonical
        }

        lock.lock()
        defer { lock.unlock() }
        var dictionary = try loadLocked()
        if let index = dictionary.replacements.firstIndex(where: {
            $0.canonical.caseInsensitiveCompare(cleanCanonical) == .orderedSame
        }) {
            let exists = dictionary.replacements[index].variants.contains {
                $0.caseInsensitiveCompare(cleanVariant) == .orderedSame
            }
            if !exists {
                dictionary.replacements[index].variants.append(cleanVariant)
            }
        } else {
            dictionary.replacements.append(
                DictionaryReplacement(canonical: cleanCanonical, variants: [cleanVariant])
            )
        }

        let validated = try dictionary.validated()
        try writeLocked(validated)
        lastValid = validated
    }

    private func loadLocked() throws -> PersonalDictionary {
        if !fileManager.fileExists(atPath: fileURL.path) {
            try writeLocked(.starter)
            lastValid = .starter
            return .starter
        }

        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(PersonalDictionary.self, from: data)
        let validated = try decoded.validated()
        try secureExistingPaths()
        lastValid = validated
        return validated
    }

    private func writeLocked(_ dictionary: PersonalDictionary) throws {
        try createPrivateRoot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(dictionary)
        data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func createPrivateRoot() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: rootDirectory.path
        )
    }

    private func secureExistingPaths() throws {
        try createPrivateRoot()
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
