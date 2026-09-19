import Foundation

struct TriageCache: Sendable {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.legacySharedURL
        }
    }

    static func forAccount(email: String) -> TriageCache {
        TriageCache(fileURL: accountURL(email: email))
    }

    static var legacySharedURL: URL {
        supportDirectory.appending(path: "triage-cache.json")
    }

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "MailJay", directoryHint: .isDirectory)
    }

    static func accountDirectory(email: String) -> URL {
        let safe = email
            .lowercased()
            .replacingOccurrences(of: "@", with: "_at_")
            .replacingOccurrences(of: "[^a-z0-9._+-]", with: "_", options: .regularExpression)
        return supportDirectory
            .appending(path: "accounts", directoryHint: .isDirectory)
            .appending(path: safe, directoryHint: .isDirectory)
    }

    static func accountURL(email: String) -> URL {
        accountDirectory(email: email).appending(path: "triage-cache.json")
    }

    func load() -> [TriageResult] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([TriageResult].self, from: data)) ?? []
    }

    func save(_ results: [TriageResult]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(results)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Moves the pre-multi-account shared cache into the first account folder once.
    static func migrateLegacyCacheIfNeeded(into email: String) {
        let destination = accountURL(email: email)
        let source = legacySharedURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path),
              !fm.fileExists(atPath: destination.path) else { return }
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: source, to: destination)
        } catch {
            // Best-effort; a failed move just means the user rescans.
        }
    }
}
