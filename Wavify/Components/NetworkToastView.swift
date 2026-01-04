//
//  NetworkToastView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 04/01/26.
//

import SwiftUI

struct NetworkToastView: View {
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var showToast: Bool = false
    @State private var isBackOnline: Bool = false
    @State private var dismissTask: Task<Void, Never>?
    
    var body: some View {
        VStack {
            if showToast {
                HStack(spacing: 8) {
                    Image(systemName: isBackOnline ? "wifi" : "wifi.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    
                    Text(isBackOnline ? "Back Online" : "No Internet Connection")
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
        }
        .padding(.top, 40)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showToast)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isBackOnline)
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            handleConnectivityChange(isConnected: newValue)
        }
        .onAppear {
            // Initial state check
            if !networkMonitor.isConnected {
                showToast = true
                isBackOnline = false
            }
        }
    }
    
    private func handleConnectivityChange(isConnected: Bool) {
        // Cancel any pending dismiss task
        dismissTask?.cancel()
        dismissTask = nil
        
        if isConnected {
            // Connection restored
            if showToast {
                // Animate to "Back Online"
                isBackOnline = true
                
                // Dismiss after 1 second
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled {
                        await MainActor.run {
                            showToast = false
                            isBackOnline = false
                        }
                    }
                }
            }
        } else {
            // Connection lost
            isBackOnline = false
            showToast = true
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
