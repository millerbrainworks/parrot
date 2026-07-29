import Foundation

final class HistoryWriter {
    static let defaultRootDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Parrot/history", isDirectory: true)

    let rootDirectory: URL
    private let calendar: Calendar
    private let queue = DispatchQueue(label: "com.digimata.parrot.history")
    private let fileManager: FileManager

    init(
        rootDirectory: URL = HistoryWriter.defaultRootDirectory,
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.calendar = calendar
        self.fileManager = fileManager
    }

    @discardableResult
    func append(
        text: String,
        applicationName: String,
        at date: Date = Date()
    ) throws -> URL? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return try queue.sync {
            let url = fileURL(for: date)
            try createPrivateDirectory(url.deletingLastPathComponent())

            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(
                    atPath: url.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )

            let time = Self.timeFormatter(calendar: calendar).string(from: date)
            let entry = "## \(time) — \(applicationName)\n\n\(text)\n\n"
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(entry.utf8))
            try handle.synchronize()
            return url
        }
    }

    func fileURL(for date: Date = Date()) -> URL {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return rootDirectory
            .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
            .appendingPathComponent(
                String(format: "%04d-%02d-%02d.md", year, month, day),
                isDirectory: false
            )
    }

    private func createPrivateDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var current = directory
        while current.path.hasPrefix(rootDirectory.path) {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: current.path
            )
            if current == rootDirectory { break }
            current.deleteLastPathComponent()
        }
    }

    private static func timeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}
