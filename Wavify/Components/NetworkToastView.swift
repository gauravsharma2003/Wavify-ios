//
//  NetworkToastView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 04/01/26.
//

import SwiftUI

struct NetworkToastView: View {
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var audioPlayer = AudioPlayer.shared
    @State private var toastManager = ToastManager.shared

    // Connectivity states
    @State private var showNoInternetToast: Bool = false
    @State private var isBackOnline: Bool = false
    @State private var noInternetDismissTask: Task<Void, Never>?

    // Slow connection states
    @State private var showSlowNetworkToast: Bool = false
    @State private var bufferingTimer: Task<Void, Never>?

    // Session state
    static var hasDismissedSlowNetworkToast = false
    
    var body: some View {
        VStack {
            if showNoInternetToast {
                // No Internet Toast (High Priority)
                HStack(spacing: 8) {
                    Image(systemName: isBackOnline ? "wifi" : "wifi.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    
                    Text(isBackOnline ? "And... we're back!" : "The internet has left the chat.")
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2) // Ensure it stays on top of slow network toast if transitioning
                
            } else if showSlowNetworkToast {
                // Slower Network Toast (Lower Priority)
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Your internet is having a lazy day.")
                        .font(.system(size: 14, weight: .semibold))
                    
                    // Close button
                    Button {
                        withAnimation {
                            showSlowNetworkToast = false
                            Self.hasDismissedSlowNetworkToast = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 4)
                }
                .foregroundStyle(.primary)
                .padding(.leading, 16)
                .padding(.trailing, 8) // Less padding on right for button
                .padding(.vertical, 6) // Slightly reduce vertical padding to compensate for larger button
                .glassEffect(.regular.interactive(), in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)

            } else if let actionToast = toastManager.currentToast {
                HStack(spacing: 8) {
                    Image(systemName: actionToast.icon)
                        .font(.system(size: 14, weight: .semibold))

                    Text(actionToast.text)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(0)
            }

            Spacer()
        }
        .padding(.top, 40)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showNoInternetToast)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSlowNetworkToast)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isBackOnline)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastManager.currentToast)
        // Monitor Network
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            handleConnectivityChange(isConnected: newValue)
        }
        // Monitor Buffering/Slow Network
        .onChange(of: audioPlayer.isBuffering) { oldValue, isBuffering in
             handleBufferingChange(isBuffering: isBuffering)
        }
        .onAppear {
            // Initial state check
            if !networkMonitor.isConnected {
                showNoInternetToast = true
                isBackOnline = false
            } else if audioPlayer.isBuffering {
                 handleBufferingChange(isBuffering: true)
            }
        }
    }
    
    private func handleConnectivityChange(isConnected: Bool) {
        // Cancel any pending dismiss task
        noInternetDismissTask?.cancel()
        noInternetDismissTask = nil
        
        if isConnected {
            // Connection restored
            if showNoInternetToast {
                // Animate to "Back Online"
                isBackOnline = true
                
                // Dismiss after 1 second
                noInternetDismissTask = Task {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled {
                        await MainActor.run {
                            showNoInternetToast = false
                            isBackOnline = false
                            
                            // Re-evaluate slow network toast after "No Internet" is gone
                            if audioPlayer.isBuffering {
                                handleBufferingChange(isBuffering: true)
                            }
                        }
                    }
                }
            } else {
                 // Even if toast wasn't shown, check slow network status
                 if audioPlayer.isBuffering {
                      handleBufferingChange(isBuffering: true)
                 }
            }
        } else {
            // Connection lost
            isBackOnline = false
            showNoInternetToast = true
            
            // Hide slow network toast if we lost internet completely
            showSlowNetworkToast = false
        }
    }
    
    private func handleBufferingChange(isBuffering: Bool) {
        // If user already dismissed it this session, don't show again
        guard !Self.hasDismissedSlowNetworkToast else { return }
        
        // If "No Internet" is showing, don't show slow network toast
        guard !showNoInternetToast else { return }
        
        bufferingTimer?.cancel()
        bufferingTimer = nil
        
        if isBuffering {
            // Wait for 3 seconds of continuous buffering before showing toast
            bufferingTimer = Task {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled {
                    await MainActor.run {
                        // Double check conditions
                        if !showNoInternetToast && !Self.hasDismissedSlowNetworkToast {
                            showSlowNetworkToast = true
                        }
                    }
                }
            }
        } else {
            // Buffering resolved - hide toast
            showSlowNetworkToast = false
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue, .teal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        NetworkToastView()
    }
}
