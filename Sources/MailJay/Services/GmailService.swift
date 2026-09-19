import Foundation

struct GmailService {
    private let http: HTTPClient
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func profileEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "profile"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let profile: Profile = try await http.send(request)
        let email = profile.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { throw ProfileError.missingEmail }
        return email
    }

    private struct Profile: Decodable {
        let emailAddress: String
    }

    enum ProfileError: LocalizedError {
        case missingEmail
        var errorDescription: String? { "Google did not return a Gmail address for this account." }
    }

    func inboxMessages(
        accessToken: String,
        maximum: Int,
        excluding knownMessageIDs: Set<String>
    ) async throws -> [MailMessage] {
        var references: [MessageReference] = []
        var pageToken: String?

        repeat {
            let page = try await messagePage(accessToken: accessToken, pageToken: pageToken)
            references.append(contentsOf: (page.messages ?? []).filter { !knownMessageIDs.contains($0.id) })
            pageToken = page.nextPageToken
        } while references.count < maximum && pageToken != nil

        // Gmail enforces a per-user concurrent request ceiling. Fetching every
        // message body in a task group can exhaust it even for a small inbox.
        // A sequential pass is fast enough for this personal review workflow
        // and leaves headroom for Gmail itself and other signed-in clients.
        var messages: [MailMessage] = []
        for item in references.prefix(maximum) {
            let fetched = try await withRateLimitRetry {
                try await message(id: item.id, accessToken: accessToken)
            }
            messages.append(fetched)
        }
        return messages.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func messagePage(accessToken: String, pageToken: String?) async throws -> MessageList {
        var components = URLComponents(url: baseURL.appending(path: "messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "labelIds", value: "INBOX"),
            URLQueryItem(name: "maxResults", value: "100")
        ]
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await withRateLimitRetry { try await http.send(request) }
    }

    /// Applies archive/delete to many messages via Gmail bulk endpoints.
    /// Archive groups by target labels (category label + remove INBOX).
    /// Delete moves to Trash with `batchModify` (add TRASH, remove INBOX) —
    /// same recoverable behavior as `messages/trash`, without per-id round trips.
    func apply(
        _ results: [TriageResult],
        action: MailAction,
        accessToken: String,
        labelIDs: [String: String]
    ) async throws {
        guard !results.isEmpty else { return }

        switch action {
        case .delete:
            let ids = results.map(\.message.id)
            for chunk in ids.chunked(into: Self.batchModifyLimit) {
                try await withRateLimitRetry {
                    try await batchModify(
                        ids: chunk,
                        add: ["TRASH"],
                        remove: ["INBOX"],
                        accessToken: accessToken
                    )
                }
            }
        case .archive:
            var groups: [[String]: [String]] = [:]
            for result in results {
                var add: [String] = []
                if let labelID = labelIDs[result.bucket] {
                    add.append(labelID)
                }
                groups[add, default: []].append(result.message.id)
            }
            for (add, ids) in groups {
                for chunk in ids.chunked(into: Self.batchModifyLimit) {
                    try await withRateLimitRetry {
                        try await batchModify(
                            ids: chunk,
                            add: add,
                            remove: ["INBOX"],
                            accessToken: accessToken
                        )
                    }
                }
            }
        }
    }

    private static let batchModifyLimit = 1000

    func ensureTriageLabels(
        accessToken: String,
        categories: [MailCategory]
    ) async throws -> [String: String] {
        var request = URLRequest(url: baseURL.appending(path: "labels"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let existing: LabelList = try await http.send(request)
        var result: [String: String] = [:]
        let desired = categories.compactMap { category -> (String, String)? in
            guard let suffix = category.gmailLabelName, !suffix.isEmpty else { return nil }
            return (category.id, "Jev/\(suffix)")
        }
        for (categoryID, name) in desired {
            if let label = existing.labels?.first(where: { $0.name == name }) {
                result[categoryID] = label.id
            } else {
                result[categoryID] = try await createLabel(name, accessToken: accessToken).id
            }
        }
        return result
    }

    private func message(id: String, accessToken: String) async throws -> MailMessage {
        var components = URLComponents(url: baseURL.appending(path: "messages/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: GmailMessage = try await http.send(request)
        let headers = normalizedHeaderDictionary(
            (response.payload.headers ?? []).map { (name: $0.name, value: $0.value) }
        )
        let plainBody = decodePart(response.payload, mimeType: "text/plain")
        let htmlBody = decodePart(response.payload, mimeType: "text/html")
        let body = plainBody ?? htmlBody.map(HTMLText.plainText) ?? response.snippet
        let timestamp = response.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
        return MailMessage(
            id: response.id,
            threadID: response.threadId,
            sender: headers["from"] ?? "Unknown sender",
            subject: headers["subject"] ?? "(No subject)",
            date: timestamp,
            snippet: response.snippet,
            body: body,
            htmlBody: htmlBody
        )
    }

    private func decodePart(_ part: MessagePart, mimeType: String) -> String? {
        if part.mimeType == mimeType,
           let encoded = part.body.data,
           let data = Data(base64URLEncoded: encoded),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        for child in part.parts ?? [] {
            if let decoded = decodePart(child, mimeType: mimeType) { return decoded }
        }
        return nil
    }

    private func batchModify(
        ids: [String],
        add: [String],
        remove: [String],
        accessToken: String
    ) async throws {
        var request = URLRequest(url: baseURL.appending(path: "messages/batchModify"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            BatchModifyRequest(ids: ids, addLabelIds: add, removeLabelIds: remove)
        )
        try await http.send(request)
    }

    private func createLabel(_ name: String, accessToken: String) async throws -> Label {
        var request = URLRequest(url: baseURL.appending(path: "labels"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateLabelRequest(name: name, labelListVisibility: "labelShow", messageListVisibility: "show"))
        return try await http.send(request)
    }

    private func withRateLimitRetry<T>(
        attempts: Int = 4,
        operation: () async throws -> T
    ) async throws -> T {
        var delay: UInt64 = 750_000_000
        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch HTTPClient.HTTPError.server(let status, _) where status == 429 && attempt < attempts {
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
            } catch {
                throw error
            }
        }
        fatalError("Rate-limit retry loop exhausted without returning or throwing")
    }

    private struct MessageList: Decodable {
        let messages: [MessageReference]?
        let nextPageToken: String?
    }
    private struct MessageReference: Decodable { let id: String }
    private struct GmailMessage: Decodable {
        let id: String
        let threadId: String
        let internalDate: String?
        let snippet: String
        let payload: MessagePart
    }
    private struct MessagePart: Decodable {
        let mimeType: String?
        let headers: [Header]?
        let body: MessageBody
        let parts: [MessagePart]?
    }
    private struct MessageBody: Decodable { let data: String? }
    private struct Header: Decodable { let name: String; let value: String }
    private struct LabelList: Decodable { let labels: [Label]? }
    private struct Label: Codable { let id: String; let name: String }
    private struct BatchModifyRequest: Encodable {
        let ids: [String]
        let addLabelIds: [String]
        let removeLabelIds: [String]
    }
    private struct CreateLabelRequest: Encodable {
        let name: String
        let labelListVisibility: String
        let messageListVisibility: String
    }
}
