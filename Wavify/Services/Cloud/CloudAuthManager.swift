//
//  CloudAuthManager.swift
//  Wavify
//
//  Google OAuth 2.0 authentication for Google Drive
//

import Foundation
import AuthenticationServices
import SwiftUI

@MainActor
@Observable
final class CloudAuthManager {
    static let shared = CloudAuthManager()

    var isAuthenticated: Bool = false
    var currentUserEmail: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiryDate: Date?

    private let clientId = "617560597580-7gsqa72b09uhst3hd7glbqr88kvan069.apps.googleusercontent.com"
    private let redirectURI = "com.googleusercontent.apps.617560597580-7gsqa72b09uhst3hd7glbqr88kvan069:/oauth2callback"
    private let scope = "https://www.googleapis.com/auth/drive.readonly email profile"

    private let accessTokenKey = "cloud_access_token"
    private let refreshTokenKey = "cloud_refresh_token"
    private let tokenExpiryKey = "cloud_token_expiry"
    private let userEmailKey = "cloud_user_email"

    private init() {
        loadStoredTokens()
    }

    // MARK: - Public Methods

    func signIn() async throws {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            throw AuthError.invalidConfiguration
        }

        let presentationContext = CloudWebAuthPresentationContext()
        let callbackURLScheme = "com.googleusercontent.apps.617560597580-7gsqa72b09uhst3hd7glbqr88kvan069"
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.authenticationFailed)
                }
            }

            session.presentationContextProvider = presentationContext
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.authenticationFailed
        }

        try await exchangeCodeForToken(code)
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiryDate = nil
        currentUserEmail = nil
        isAuthenticated = false
        clearStoredTokens()
    }

    func getAccessToken() async throws -> String {
        if let token = accessToken,
           let expiry = tokenExpiryDate,
           expiry > Date().addingTimeInterval(60) {
            return token
        }

        if let refreshToken = refreshToken {
            try await refreshAccessToken(refreshToken)
            guard let token = accessToken else {
                throw AuthError.tokenRefreshFailed
            }
            return token
        }

        throw AuthError.notAuthenticated
    }

    // MARK: - Private Methods

    private func exchangeCodeForToken(_ code: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        accessToken = response.access_token
        refreshToken = response.refresh_token
        tokenExpiryDate = Date().addingTimeInterval(TimeInterval(response.expires_in))
        isAuthenticated = true

        await fetchUserInfo()
        saveTokens()
    }

    private func refreshAccessToken(_ refreshToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        accessToken = response.access_token
        tokenExpiryDate = Date().addingTimeInterval(TimeInterval(response.expires_in))
        isAuthenticated = true
        saveTokens()
    }

    private func fetchUserInfo() async {
        guard let token = accessToken else { return }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
            currentUserEmail = userInfo.email
        } catch {
            currentUserEmail = "Signed In"
        }
        saveTokens()
    }

    // MARK: - Token Storage

    private func saveTokens() {
        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        UserDefaults.standard.set(tokenExpiryDate, forKey: tokenExpiryKey)
        UserDefaults.standard.set(currentUserEmail, forKey: userEmailKey)
    }

    private func loadStoredTokens() {
        accessToken = UserDefaults.standard.string(forKey: accessTokenKey)
        refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey)
        tokenExpiryDate = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date
        currentUserEmail = UserDefaults.standard.string(forKey: userEmailKey)

        if accessToken != nil || refreshToken != nil {
            isAuthenticated = true
        }
    }

    private func clearStoredTokens() {
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
    }

    // MARK: - Types

    enum AuthError: LocalizedError {
        case invalidConfiguration
        case authenticationFailed
        case tokenRefreshFailed
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: return "OAuth configuration is invalid"
            case .authenticationFailed: return "Failed to authenticate with Google"
            case .tokenRefreshFailed: return "Failed to refresh access token"
            case .notAuthenticated: return "Not authenticated. Please sign in first."
            }
        }
    }

    private struct TokenResponse: Codable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
        let scope: String?
        let token_type: String
    }

    private struct UserInfo: Codable {
        let email: String?
        let name: String?
        let picture: String?
    }
}

// MARK: - Presentation Context

class CloudWebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}
