import Foundation

struct JevService {
    private let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func classify(
        _ message: MailMessage,
        apiKey: String,
        threshold: Double,
        categories: [MailCategory]
    ) async throws -> TriageResult {
        let state = """
        From: \(message.sender)
        Subject: \(message.subject)
        Gmail snippet: \(message.snippet)
        Message body:
        \(HTMLText.limited(message.body))
        """
        var criteria = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.modelDescription) })
        criteria[CategoryID.uncertain] = MailCategory.uncertain.modelDescription

        let requestBody = JevRequest(
            state: state,
            model: "jev-latest",
            questions: [
                "mail_bucket": ChoiceQuestion(
                    type: "choice",
                    instructions: "Classify this personal inbox email by the single best next action. Prefer uncertain whenever evidence is weak or categories overlap.",
                    criteria: criteria
                )
            ]
        )
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        let response: JevResponse = try await http.send(request)
        guard let answer = response.answers["mail_bucket"] else { throw JevError.missingAnswer }
        let knownIDs = Set(categories.map(\.id) + [CategoryID.uncertain])
        let predicted = knownIDs.contains(answer.choice) ? answer.choice : CategoryID.uncertain
        let probabilities = answer.probabilities.filter { knownIDs.contains($0.key) }
        return .fromPrediction(
            message: message,
            predicted: predicted,
            confidence: answer.confidence,
            probabilities: probabilities,
            threshold: threshold
        )
    }

    private struct JevRequest: Encodable {
        let state: String
        let model: String
        let questions: [String: ChoiceQuestion]
    }

    private struct ChoiceQuestion: Encodable {
        let type: String
        let instructions: String
        let criteria: [String: String]
    }

    private struct JevResponse: Decodable {
        let answers: [String: ChoiceAnswer]
    }

    private struct ChoiceAnswer: Decodable {
        let choice: String
        let probabilities: [String: Double]
        let confidence: Double
    }

    enum JevError: LocalizedError {
        case missingAnswer
        var errorDescription: String? { "Jev did not return a mail_bucket answer." }
    }
}
