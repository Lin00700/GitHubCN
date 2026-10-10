import SwiftUI
import AuthenticationServices
import UIKit
import CryptoKit

/// Native Google OAuth 2.0 Authorization Code + PKCE.
/// Configure clientID with an OAuth Client ID of type iOS from Google Cloud Console.
@MainActor
final class GoogleSignInManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleSignInManager()

    // Replace this with your Google Cloud Console iOS OAuth Client ID.
    // Example format: 123456789-abcdefg.apps.googleusercontent.com
    private let clientID = "YOUR_GOOGLE_IOS_CLIENT_ID.apps.googleusercontent.com"

    @Published private(set) var displayName: String?
    @Published private(set) var email: String?
    @Published private(set) var errorMessage: String?
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<GoogleProfile, Error>?

    private var reversedClientID: String {
        // Google iOS URL scheme format: com.googleusercontent.apps.<client-id-prefix>
        let prefix = clientID.components(separatedBy: ".apps.googleusercontent.com").first ?? clientID
        return "com.googleusercontent.apps." + prefix
    }

    private var redirectURI: String { "\(reversedClientID):/oauthredirect" }

    func signIn() async throws -> GoogleProfile {
        guard !clientID.hasPrefix("YOUR_") else {
            throw GoogleAuthError.notConfigured
        }
        errorMessage = nil
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafeString(length: 24)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "include_granted_scopes", value: "true")
        ]
        guard let authURL = components.url else { throw GoogleAuthError.invalidURL }
        let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: reversedClientID) { url, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: GoogleAuthError.noCallback); return }
                continuation.resume(returning: url)
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            self.session = authSession
            if !authSession.start() { continuation.resume(throwing: GoogleAuthError.couldNotStart) }
        }
        guard let callbackParts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let returnedState = callbackParts.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state else { throw GoogleAuthError.stateMismatch }
        if let error = callbackParts.queryItems?.first(where: { $0.name == "error" })?.value {
            throw GoogleAuthError.provider(error)
        }
        guard let code = callbackParts.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.noCode
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (tokenData, tokenResponse) = try await URLSession.shared.data(for: request)
        guard let http = tokenResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleAuthError.tokenExchange(String(data: tokenData, encoding: .utf8) ?? "HTTP error")
        }
        let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: tokenData)
        var profileRequest = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        profileRequest.setValue("Bearer \(token.access_token)", forHTTPHeaderField: "Authorization")
        let (profileData, profileResponse) = try await URLSession.shared.data(for: profileRequest)
        guard let profileHTTP = profileResponse as? HTTPURLResponse, (200..<300).contains(profileHTTP.statusCode) else {
            throw GoogleAuthError.profileFetch
        }
        let profile = try JSONDecoder().decode(GoogleProfile.self, from: profileData)
        displayName = profile.name
        email = profile.email
        UserDefaults.standard.set(profile.name, forKey: "google.profile.name")
        UserDefaults.standard.set(profile.email, forKey: "google.profile.email")
        return profile
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private static func randomURLSafeString(length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct GoogleProfile: Decodable {
    let id: String?
    let email: String?
    let name: String?
    let picture: String?
}

private struct GoogleTokenResponse: Decodable {
    let access_token: String
    let token_type: String?
    let expires_in: Int?
    let id_token: String?
}

private enum GoogleAuthError: LocalizedError {
    case notConfigured, invalidURL, noCallback, couldNotStart, stateMismatch, noCode, profileFetch
    case provider(String), tokenExchange(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "请先在 GoogleSignIn.swift 中填写 Google Cloud 的 iOS OAuth Client ID。"
        case .invalidURL: return "无法创建 Google 登录地址。"
        case .noCallback: return "没有收到 Google 登录回调。"
        case .couldNotStart: return "无法打开系统安全登录窗口。"
        case .stateMismatch: return "OAuth state 校验失败，请重试。"
        case .noCode: return "Google 没有返回授权码。"
        case .profileFetch: return "登录成功，但读取 Google 资料失败。"
        case .provider(let value): return "Google 登录未完成：\(value)"
        case .tokenExchange(let value): return "Google 令牌交换失败：\(value)"
        }
    }
}
