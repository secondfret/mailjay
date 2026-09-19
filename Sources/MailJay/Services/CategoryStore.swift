import Foundation

/// Per-account category definitions stored next to the triage cache.
struct CategoryStore: Sendable {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func forAccount(email: String) -> CategoryStore {
        CategoryStore(fileURL: TriageCache.accountDirectory(email: email).appending(path: "categories.json"))
    }

    func load() -> [MailCategory] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MailCategory].self, from: data),
              !decoded.isEmpty else {
            return MailCategory.defaults
        }
        let categories = decoded.sorted { $0.sortOrder < $1.sortOrder }
        // Rewrite legacy blobs (e.g. unused `modelLabel`) into the Jev-focused schema
        // without wiping the user's categories.
        if needsSchemaRewrite(data) {
            try? save(categories)
        }
        return categories
    }

    func save(_ categories: [MailCategory]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ordered = categories.enumerated().map { index, category -> MailCategory in
            var copy = category
            copy.sortOrder = index
            return copy
        }
        let data = try JSONEncoder().encode(ordered)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func needsSchemaRewrite(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("\"modelLabel\"")
    }
}
