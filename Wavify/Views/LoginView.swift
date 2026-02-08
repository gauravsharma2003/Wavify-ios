//
//  LoginView.swift
//  Wavify
//
//  Login screen shown when user is not authenticated
//

import SwiftUI

/// Login screen with Google authentication for YouTube Music
struct LoginView: View {
    @ObservedObject private var authManager = AuthenticationManager.shared
    @State private var showWebView = false
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            // Background
            Color(hex: "1A1A1A")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo and branding
                VStack(spacing: 24) {
                    // App icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "FF6B6B"), Color(hex: "C44569")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color(hex: "FF6B6B").opacity(0.4), radius: 20, x: 0, y: 10)
                    
                    // App name
                    Text("Wavify")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    // Tagline
                    Text("Your music, your way")
                        .font(.title3)
                        .foregroundStyle(.gray)
                }
                
                Spacer()
                
                // Features list
                VStack(spacing: 16) {
                    FeatureRow(icon: "waveform", text: "Stream millions of songs")
                    FeatureRow(icon: "heart.fill", text: "Create your own playlists")
                    FeatureRow(icon: "music.note.list", text: "Discover new music")
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Login button
                Button(action: {
                    showWebView = true
                }) {
                    HStack(spacing: 12) {
                        if isLoading {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                        }
                        
                        Text("Sign in with Google")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .disabled(isLoading)
                
                // Privacy note
                Text("By signing in, you agree to our Terms of Service and Privacy Policy")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showWebView) {
            NavigationStack {
                LoginWebView { cookies, visitorData, dataSyncId in
                    isLoading = true
                    showWebView = false
                    
                    // Store credentials
                    Task { @MainActor in
                        authManager.storeCredentials(
                            cookies: cookies,
                            visitorData: visitorData,
                            dataSyncId: dataSyncId
                        )
                        isLoading = false
                    }
                }
                .navigationTitle("Sign in to YouTube Music")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showWebView = false
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

/// Feature row for the login screen
private struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color(hex: "FF6B6B"))
                .frame(width: 32)
            
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
}

#Preview {
    LoginView()
}
