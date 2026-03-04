//
//  ShakeDetector.swift
//  Wavify
//
//  Shake the device/simulator to simulate an audio interruption.
//  Simulator shortcut: Hardware → Shake Gesture (⌃⌘Z)
//

#if DEBUG
import SwiftUI

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .debugShakeDetected, object: nil)
        }
    }
}

extension Notification.Name {
    static let debugShakeDetected = Notification.Name("debugShakeDetected")
}

struct DebugShakeModifier: ViewModifier {
    @State private var showToast = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .debugShakeDetected)) { _ in
                AudioPlayer.shared.simulateInterruption()
                showToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
            .overlay(alignment: .top) {
                if showToast {
                    Text("Simulating phone call interruption...")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: showToast)
                }
            }
    }
}

extension View {
    func debugShakeToSimulateInterruption() -> some View {
        modifier(DebugShakeModifier())
    }
}
#endif
