import UIKit

/// Manages keyboard pre-warming to reduce latency on first use.
/// This runs strictly on the MainActor as it involves UIKit view manipulation.
@MainActor
class KeyboardManager {
    static let shared = KeyboardManager()
    
    private var hasPrewarmed = false
    
    private init() {}
    
    /// Pre-warms the keyboard by briefly making a hidden text field the first responder.
    /// This is done asynchronously to avoid blocking the main thread during app launch.
    func prewarmKeyboard() {
        guard !hasPrewarmed else { return }
        hasPrewarmed = true
        
        Task {
            // Delay slightly to ensure the app's initial UI rendering isn't affected
            // and the window is likely ready.
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Perform the pre-warming
            performPrewarm()
        }
    }
    
    private func performPrewarm() {
        // We need an active window to attach the text field to
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return
        }
        
        let textField = UITextField()
        textField.alpha = 0
        window.addSubview(textField)
        
        // Use performWithoutAnimation to prevent any sliding up/down animations
        UIView.performWithoutAnimation {
            // Trigger keyboard loading
            textField.becomeFirstResponder()
            // Immediately resign to hide it, but the resource loading side-effect persists
            textField.resignFirstResponder()
        }
        
        textField.removeFromSuperview()
    }
}
