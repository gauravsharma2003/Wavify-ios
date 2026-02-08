//
//  LoginWebView.swift
//  Wavify
//
//  WKWebView wrapper for Google OAuth authentication
//

import SwiftUI
import WebKit

/// Coordinator for handling WKWebView navigation and JavaScript callbacks
class LoginWebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var parent: LoginWebView
    
    private var visitorData: String?
    private var dataSyncId: String?
    private var hasExtractedCredentials = false
    
    init(parent: LoginWebView) {
        self.parent = parent
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "visitorDataHandler":
            if let data = message.body as? String, !data.isEmpty {
                visitorData = data
                Logger.log("Extracted VISITOR_DATA", category: .network, level: .debug)
            }
        case "dataSyncIdHandler":
            if let data = message.body as? String, !data.isEmpty {
                dataSyncId = data
                Logger.log("Extracted DATASYNC_ID", category: .network, level: .debug)
            }
        default:
            break
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        
        // Debug: Log every page load
        Logger.log("WebView loaded: \(url.host ?? "unknown") - path: \(url.path)", category: .network, level: .debug)
        
        // Inject JavaScript to extract VISITOR_DATA and DATASYNC_ID
        let extractionScript = """
        (function() {
            try {
                if (window.yt && window.yt.config_) {
                    if (window.yt.config_.VISITOR_DATA) {
                        window.webkit.messageHandlers.visitorDataHandler.postMessage(window.yt.config_.VISITOR_DATA);
                    }
                    if (window.yt.config_.DATASYNC_ID) {
                        window.webkit.messageHandlers.dataSyncIdHandler.postMessage(window.yt.config_.DATASYNC_ID);
                    }
                }
            } catch(e) {
                console.log('Error extracting YT config: ' + e);
            }
        })();
        """
        
        webView.evaluateJavaScript(extractionScript) { _, error in
            if let error = error {
                Logger.log("JS extraction error: \(error.localizedDescription)", category: .network, level: .debug)
            }
        }
        
        // Check if we're on YouTube Music after login
        let isYouTubeMusic = url.host?.contains("music.youtube.com") == true
        Logger.log("Is YouTube Music: \(isYouTubeMusic), hasExtracted: \(hasExtractedCredentials)", category: .network, level: .debug)
        
        if isYouTubeMusic && !hasExtractedCredentials {
            hasExtractedCredentials = true
            Logger.log("Starting cookie extraction...", category: .network, level: .info)
            extractCookiesAndComplete(from: webView)
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow all navigation
        decisionHandler(.allow)
    }
    
    // MARK: - Cookie Extraction
    
    private func extractCookiesAndComplete(from webView: WKWebView) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            
            // Debug: Log total cookies found
            Logger.log("Total cookies found: \(cookies.count)", category: .network, level: .debug)
            
            // Filter YouTube/Google cookies and format as cookie string
            let relevantCookies = cookies.filter { cookie in
                cookie.domain.contains("youtube.com") || cookie.domain.contains("google.com")
            }
            
            Logger.log("Relevant cookies: \(relevantCookies.count)", category: .network, level: .debug)
            
            guard !relevantCookies.isEmpty else {
                Logger.log("No relevant cookies found", category: .network, level: .warning)
                return
            }
            
            // Build cookie string
            let cookieString = relevantCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            
            // Check if we have SAPISID (required for auth)
            let hasSapisid = relevantCookies.contains { $0.name == "SAPISID" }
            
            // Also check for __Secure-3PAPISID which is sometimes used instead
            let hasSecureSapisid = relevantCookies.contains { $0.name == "__Secure-3PAPISID" }
            
            Logger.log("Has SAPISID: \(hasSapisid), Has __Secure-3PAPISID: \(hasSecureSapisid)", category: .network, level: .debug)
            
            // Debug: List all cookie names
            let cookieNames = relevantCookies.map { $0.name }.joined(separator: ", ")
            Logger.log("Cookie names: \(cookieNames)", category: .network, level: .debug)
            
            if hasSapisid || hasSecureSapisid {
                Logger.log("Successfully extracted authentication cookies", category: .network, level: .info)
                
                DispatchQueue.main.async {
                    self.parent.onLoginComplete(cookieString, self.visitorData, self.dataSyncId)
                }
            } else {
                Logger.log("Waiting for SAPISID cookie...", category: .network, level: .debug)
                // Retry after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.hasExtractedCredentials = false
                    self?.extractCookiesAndComplete(from: webView)
                }
            }
        }
    }
}

/// SwiftUI wrapper for WKWebView to handle Google OAuth login
struct LoginWebView: UIViewRepresentable {
    let onLoginComplete: (String, String?, String?) -> Void
    
    func makeCoordinator() -> LoginWebViewCoordinator {
        LoginWebViewCoordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Add script message handlers
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "visitorDataHandler")
        contentController.add(context.coordinator, name: "dataSyncIdHandler")
        configuration.userContentController = contentController
        
        // Enable JavaScript
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Create WebView
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Set custom user agent to appear as desktop browser
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        
        // Load Google login page
        let loginURL = URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com")!
        webView.load(URLRequest(url: loginURL))
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
}

#Preview {
    LoginWebView { cookies, visitorData, dataSyncId in
        print("Login complete: \(cookies.prefix(50))...")
    }
}
