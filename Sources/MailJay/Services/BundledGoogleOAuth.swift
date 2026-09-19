import Foundation

/// Google Desktop OAuth client credentials embedded at build time.
///
/// Desktop client secrets are not confidential (Google documents this). End users
/// never enter them — developers put values in `Config/GoogleOAuth.plist` (gitignored),
/// and `script/build_and_run.sh` copies that file into the app bundle.
enum BundledGoogleOAuth {
    static var clientID: String { credentials.clientID }
    static var clientSecret: String { credentials.clientSecret }
    static var isConfigured: Bool { !clientID.isEmpty }

    private static let credentials: (clientID: String, clientSecret: String) = load()

    private static func load() -> (clientID: String, clientSecret: String) {
        let urls = [
            Bundle.main.url(forResource: "GoogleOAuth", withExtension: "plist"),
            Bundle.main.bundleURL
                .appending(path: "Contents/Resources/GoogleOAuth.plist", directoryHint: .notDirectory)
        ]
        for case let url? in urls {
            if let values = readPlist(at: url) {
                return values
            }
        }
        return ("", "")
    }

    private static func readPlist(at url: URL) -> (clientID: String, clientSecret: String)? {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let id = stringValue(dict["ClientID"])
        let secret = stringValue(dict["ClientSecret"])
        guard !id.isEmpty else { return nil }
        return (id, secret)
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let raw = value as? String else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
