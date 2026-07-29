import Foundation

struct ParrotPreferences: Codable, Equatable {
    var microphoneUID: String?

    init(microphoneUID: String? = nil) {
        self.microphoneUID = microphoneUID
    }
}

final class PreferencesStore {
    static let defaultURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Application Support/Parrot/preferences.json",
            isDirectory: false
        )

    let url: URL
    private let fileManager: FileManager

    init(url: URL = PreferencesStore.defaultURL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> ParrotPreferences {
        guard fileManager.fileExists(atPath: url.path) else {
            return ParrotPreferences()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ParrotPreferences.self, from: data)
    }

    func save(_ preferences: ParrotPreferences) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
