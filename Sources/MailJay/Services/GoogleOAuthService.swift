import AppKit
import CryptoKit
import Darwin
import Foundation

final class GoogleOAuthService {
    private let http: HTTPClient
    private var callbackServer: OAuthCallback?

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func authorize(clientID: String, clientSecret: String) async throws -> OAuthToken {
        let callback = try await beginCallbackListener()
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString
        let state = Self.randomURLSafeString(byteCount: 24)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: callback.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/gmail.modify"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { throw OAuthError.invalidAuthorizationURL }
        NSWorkspace.shared.open(url)

        let response = try await callback.waitForResponse()
        guard response.state == state else { throw OAuthError.stateMismatch }
        if let error = response.error { throw OAuthError.authorization(error) }
        guard let code = response.code else { throw OAuthError.missingCode }
        return try await exchangeCode(
            code,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: callback.redirectURI,
            verifier: verifier
        )
    }

    func refreshedToken(_ token: OAuthToken, clientID: String, clientSecret: String) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else { throw OAuthError.missingRefreshToken }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        if !clientSecret.isEmpty { fields["client_secret"] = clientSecret }
        request.httpBody = Self.formBody(fields)
        let response: TokenResponse = try await http.send(request)
        return OAuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    private func exchangeCode(
        _ code: String,
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        verifier: String
    ) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        if !clientSecret.isEmpty { fields["client_secret"] = clientSecret }
        request.httpBody = Self.formBody(fields)
        let response: TokenResponse = try await http.send(request)
        return OAuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    private func beginCallbackListener() async throws -> OAuthCallback {
        let server = try OAuthCallback()
        callbackServer = server
        return server
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    enum OAuthError: LocalizedError {
        case invalidAuthorizationURL, listenerFailed, stateMismatch, missingCode, missingRefreshToken
        case authorization(String)

        var errorDescription: String? {
            switch self {
            case .invalidAuthorizationURL: "Could not create the Google sign-in URL."
            case .listenerFailed: "Could not start the local OAuth callback listener."
            case .stateMismatch: "The OAuth response did not match this sign-in request."
            case .missingCode: "Google did not return an authorization code."
            case .missingRefreshToken: "Google did not return a refresh token. Please connect again."
            case .authorization(let message): "Google authorization failed: \(message)"
            }
        }
    }
}

final class OAuthCallback: @unchecked Sendable {
    let redirectURI: String
    private let socketDescriptor: Int32

    init() throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError.current("Could not create the OAuth callback socket") }

        var reuse: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            Darwin.close(descriptor)
            throw POSIXError.current("Could not configure the OAuth callback socket")
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError.current("Could not bind the OAuth callback socket")
        }
        guard Darwin.listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw POSIXError.current("Could not listen for the OAuth callback")
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &boundLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError.current("Could not determine the OAuth callback port")
        }

        socketDescriptor = descriptor
        let port = UInt16(bigEndian: boundAddress.sin_port)
        self.redirectURI = "http://127.0.0.1:\(port)/oauth/callback"
    }

    deinit {
        Darwin.close(socketDescriptor)
    }

    func waitForResponse() async throws -> Response {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [socketDescriptor] in
                let client = Darwin.accept(socketDescriptor, nil, nil)
                guard client >= 0 else {
                    continuation.resume(throwing: POSIXError.current("Could not accept the OAuth callback"))
                    return
                }
                defer { Darwin.close(client) }

                var buffer = [UInt8](repeating: 0, count: 16_384)
                let count = Darwin.read(client, &buffer, buffer.count)
                guard count > 0,
                      let request = String(bytes: buffer.prefix(count), encoding: .utf8),
                      let firstLine = request.components(separatedBy: "\r\n").first,
                      let target = firstLine.split(separator: " ").dropFirst().first,
                      let url = URL(string: "http://127.0.0.1\(target)"),
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    continuation.resume(throwing: POSIXError(message: "Google returned an invalid OAuth callback."))
                    return
                }

                let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let body = "<html><body style='font-family:-apple-system;padding:40px'><h2>MailJay is connected.</h2><p>You can close this tab and return to the app.</p></body></html>"
                let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                _ = httpResponse.withCString { bytes in
                    Darwin.write(client, bytes, strlen(bytes))
                }
                continuation.resume(returning: Response(code: query["code"], state: query["state"], error: query["error"]))
            }
        }
    }

    struct Response {
        let code: String?
        let state: String?
        let error: String?
    }
}

private struct POSIXError: LocalizedError {
    let message: String

    static func current(_ context: String) -> POSIXError {
        POSIXError(message: "\(context): \(String(cString: strerror(errno)))")
    }

    var errorDescription: String? { message }
}
