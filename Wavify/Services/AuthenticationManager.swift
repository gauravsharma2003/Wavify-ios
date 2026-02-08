//
//  AuthenticationManager.swift
//  Wavify
//
//  Manages YouTube Music authentication credentials and header generation
//

import Foundation
import Security
import CryptoKit
import Combine

/// Manages authentication state and credentials for YouTube Music API
@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var isAuthenticated: Bool = false
    
    // MARK: - Keychain Keys
    
    private enum KeychainKey {
        static let cookies = "com.wavify.auth.cookies"
        static let sapisid = "com.wavify.auth.sapisid"
        static let visitorData = "com.wavify.auth.visitorData"
        static let dataSyncId = "com.wavify.auth.dataSyncId"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Check if we have stored credentials
        isAuthenticated = getSapisid() != nil && getCookies() != nil
    }
    
    // MARK: - Credential Storage
    
    /// Store authentication credentials after successful login
    func storeCredentials(cookies: String, visitorData: String?, dataSyncId: String?) {
        // Extract SAPISID from cookie string
        if let sapisid = extractSapisid(from: cookies) {
            saveToKeychain(key: KeychainKey.sapisid, value: sapisid)
        }
        
        saveToKeychain(key: KeychainKey.cookies, value: cookies)
        
        if let visitorData = visitorData {
            saveToKeychain(key: KeychainKey.visitorData, value: visitorData)
            // Also update the shared visitor data
            YouTubeAPIContext.visitorData = visitorData
        }
        
        if let dataSyncId = dataSyncId {
            saveToKeychain(key: KeychainKey.dataSyncId, value: dataSyncId)
        }
        
        isAuthenticated = true
        Logger.log("Authentication credentials stored successfully", category: .network, level: .info)
    }
    
    /// Clear all stored credentials (logout)
    func logout() {
        deleteFromKeychain(key: KeychainKey.cookies)
        deleteFromKeychain(key: KeychainKey.sapisid)
        deleteFromKeychain(key: KeychainKey.visitorData)
        deleteFromKeychain(key: KeychainKey.dataSyncId)
        
        // Reset visitor data to incognito
        YouTubeAPIContext.visitorData = YouTubeAPIContext.incognitoVisitorData
        
        isAuthenticated = false
        Logger.log("User logged out, credentials cleared", category: .network, level: .info)
    }
    
    // MARK: - Credential Retrieval
    
    func getCookies() -> String? {
        return getFromKeychain(key: KeychainKey.cookies)
    }
    
    func getSapisid() -> String? {
        return getFromKeychain(key: KeychainKey.sapisid)
    }
    
    func getVisitorData() -> String? {
        return getFromKeychain(key: KeychainKey.visitorData)
    }
    
    func getDataSyncId() -> String? {
        return getFromKeychain(key: KeychainKey.dataSyncId)
    }
    
    // MARK: - Authorization Header Generation
    
    /// Generate SAPISIDHASH authorization header
    /// Algorithm: SAPISIDHASH {timestamp}_{sha1(timestamp + " " + SAPISID + " " + origin)}
    func generateAuthorizationHeader() -> String? {
        guard let sapisid = getSapisid() else { return nil }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let origin = "https://music.youtube.com"
        let input = "\(timestamp) \(sapisid) \(origin)"
        
        // Generate SHA1 hash
        let inputData = Data(input.utf8)
        let hash = Insecure.SHA1.hash(data: inputData)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        
        return "SAPISIDHASH \(timestamp)_\(hashString)"
    }
    
    /// Get all authentication headers for API requests
    func getAuthHeaders() -> [String: String]? {
        // Debug: Log auth status
        Logger.log("Auth check - isAuthenticated: \(isAuthenticated)", category: .network, level: .debug)
        
        guard isAuthenticated else {
            Logger.log("Auth headers: User not authenticated", category: .network, level: .warning)
            return nil
        }
        
        guard let cookies = getCookies() else {
            Logger.log("Auth headers: No cookies found in keychain", category: .network, level: .warning)
            return nil
        }
        
        guard let authorization = generateAuthorizationHeader() else {
            Logger.log("Auth headers: Failed to generate SAPISIDHASH", category: .network, level: .warning)
            return nil
        }
        
        Logger.log("Auth headers: Cookies length=\(cookies.count), auth=\(authorization.prefix(30))...", category: .network, level: .debug)
        
        var headers: [String: String] = [
            "Authorization": authorization,
            "Cookie": cookies,
            "X-Origin": "https://music.youtube.com"
        ]
        
        if let visitorData = getVisitorData() {
            headers["X-Goog-Visitor-Id"] = visitorData
        }
        
        return headers
    }
    
    // MARK: - SAPISID Extraction
    
    /// Extract SAPISID value from cookie string
    private func extractSapisid(from cookieString: String) -> String? {
        // Cookie format: "SAPISID=xxx; SID=yyy; ..."
        let cookies = cookieString.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for cookie in cookies {
            let parts = cookie.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == "SAPISID" {
                return String(parts[1])
            }
        }
        
        return nil
    }
    
    // MARK: - Keychain Operations
    
    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete existing item first
        deleteFromKeychain(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.warning("Failed to save to Keychain: \(status)", category: .network)
        }
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
