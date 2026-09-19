import XCTest
@testable import MailJay

final class DataCodingTests: XCTestCase {
    func testBase64URLDecoding() {
        let encoded = Data("hello, mail".utf8).base64URLEncodedString
        XCTAssertEqual(Data(base64URLEncoded: encoded), Data("hello, mail".utf8))
    }

    func testHTMLCleanup() {
        XCTAssertEqual(HTMLText.plainText(from: "<p>Hello &amp; goodbye</p>"), "Hello & goodbye")
    }

    func testHTMLCleanupRemovesEmailTemplateNonsense() {
        let html = """
        <head><style>.hidden { display: none }</style></head>
        <p>This email includes the info you shared.</p>
        <!--[if !mso]><!--><div>Name and profile picture</div><!--<![endif]-->
        <!--[if mso]><table><tr><td>Outlook-only layout</td></tr></table><![endif]-->
        <script>doSomethingUnsafe()</script>
        """

        let text = HTMLText.plainText(from: html)

        XCTAssertEqual(text, "This email includes the info you shared. Name and profile picture")
        XCTAssertFalse(text.contains("<!--[if"))
        XCTAssertFalse(text.contains("Outlook-only"))
        XCTAssertFalse(text.contains("doSomethingUnsafe"))
    }

    func testConfigurationRequiresBundledOAuthAndJevKey() {
        XCTAssertFalse(AppConfiguration.empty.isComplete)
        let configured = AppConfiguration(
            googleClientID: "client",
            googleClientSecret: "",
            jevAPIKey: "key",
            maxMessages: 300,
            confidenceThreshold: 0.45,
            autoFetchIntervalMinutes: 15
        )
        // Completeness requires the embedded OAuth plist in this build.
        XCTAssertEqual(configured.isComplete, BundledGoogleOAuth.isConfigured)
    }

    func testLegacyCategoryJSONDropsModelLabel() throws {
        let json = """
        [
          {
            "id": "ads",
            "title": "Ads & Promos",
            "systemImage": "megaphone",
            "modelLabel": "old unused phrase",
            "modelDescription": "Promo mail.",
            "gmailLabelName": null,
            "sortOrder": 0
          }
        ]
        """
        let categories = try MailCategory.decodeList(from: json)
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories[0].id, "ads")
        XCTAssertEqual(categories[0].modelDescription, "Promo mail.")

        let rewritten = MailCategory.prettyJSON(categories)
        XCTAssertFalse(rewritten.contains("modelLabel"))
        XCTAssertTrue(rewritten.contains("modelDescription"))
    }

    func testCategoryStoreRewritesLegacySchemaInPlace() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "categories.json")
        let legacy = """
        [{"id":"ads","title":"Ads","systemImage":"megaphone","modelLabel":"promo","modelDescription":"Ads go here.","gmailLabelName":null,"sortOrder":0}]
        """.data(using: .utf8)!
        try legacy.write(to: fileURL)

        let store = CategoryStore(fileURL: fileURL)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "ads")

        let rewritten = try Data(contentsOf: fileURL)
        let text = String(data: rewritten, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("modelLabel"))
        XCTAssertTrue(text.contains("modelDescription"))
    }

    func testPredictionBelowThresholdBecomesUncertain() {
        let message = MailMessage(
            id: "id",
            threadID: "thread",
            sender: "a@b.com",
            subject: "Hi",
            date: nil,
            snippet: "",
            body: "",
            htmlBody: nil
        )
        let result = TriageResult.fromPrediction(
            message: message,
            predicted: "junk",
            confidence: 0.2,
            probabilities: ["junk": 0.2, "keep": 0.1],
            threshold: 0.45
        )
        XCTAssertEqual(result.bucket, CategoryID.uncertain)
        XCTAssertFalse(result.isSelected)
    }

    func testOAuthLoopbackCallback() async throws {
        let callback = try OAuthCallback()
        let responseTask = Task { try await callback.waitForResponse() }
        guard let url = URL(string: "\(callback.redirectURI)?code=test-code&state=test-state") else {
            return XCTFail("Could not construct callback URL")
        }

        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let callbackResponse = try await responseTask.value
        XCTAssertEqual(callbackResponse.code, "test-code")
        XCTAssertEqual(callbackResponse.state, "test-state")
        XCTAssertNil(callbackResponse.error)
    }

    func testDuplicateGmailHeadersDoNotCrash() {
        let headers = normalizedHeaderDictionary([
            (name: "Received", value: "first mail server"),
            (name: "Subject", value: "A receipt"),
            (name: "received", value: "second mail server")
        ])

        XCTAssertEqual(headers["subject"], "A receipt")
        XCTAssertEqual(headers["received"], "second mail server")
        XCTAssertEqual(headers.count, 2)
    }

    func testRenderedEmailDisablesRemoteContentAndScripts() {
        let document = EmailHTMLDocument.make(from: "<script>track()</script><p>Hello</p><img src=\"https://tracker.example/pixel\">")

        XCTAssertTrue(document.contains("Content-Security-Policy"))
        XCTAssertTrue(document.contains("img-src data:"))
        XCTAssertFalse(document.localizedCaseInsensitiveContains("<script"))
        XCTAssertTrue(document.contains("<p>Hello</p>"))
    }

    func testTriageCacheRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "triage-cache.json")
        let cache = TriageCache(fileURL: url)
        let message = MailMessage(
            id: "gmail-id",
            threadID: "thread-id",
            sender: "Sender <sender@example.com>",
            subject: "A receipt",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            snippet: "Thanks",
            body: "Receipt body",
            htmlBody: "<p>Receipt body</p>"
        )
        let result = TriageResult(
            message: message,
            bucket: "receipts",
            confidence: 0.92,
            probabilities: ["receipts": 0.92, "uncertain": 0.08],
            isSelected: true,
            isApplied: false
        )

        try cache.save([result])

        XCTAssertEqual(cache.load(), [result])
        try cache.clear()
        XCTAssertTrue(cache.load().isEmpty)
    }

    func testPerAccountTriageCachePathsDiffer() {
        let first = TriageCache.accountURL(email: "one@example.com")
        let second = TriageCache.accountURL(email: "two@example.com")
        XCTAssertNotEqual(first.path, second.path)
        XCTAssertTrue(first.path.contains("accounts"))
    }

    func testAppliedResultIsNoLongerPending() {
        let message = MailMessage(
            id: "processed-id",
            threadID: "thread-id",
            sender: "sender@example.com",
            subject: "Processed",
            date: nil,
            snippet: "",
            body: "",
            htmlBody: nil
        )
        let result = TriageResult(
            message: message,
            bucket: "junk",
            confidence: 1,
            probabilities: ["junk": 1],
            isSelected: false,
            isApplied: true
        )

        XCTAssertFalse(result.isPending)
    }
}
