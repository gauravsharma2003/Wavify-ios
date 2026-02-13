//
//  ToastManager.swift
//  Wavify
//
//  Lightweight observable for showing action toasts from anywhere in the app.
//

import SwiftUI

@Observable
@MainActor
final class ToastManager {
    static let shared = ToastManager()
    private init() {}

    private(set) var currentToast: ActionToast?
    private var dismissTask: Task<Void, Never>?

    struct ActionToast: Equatable {
        let icon: String
        let text: String
        let id: UUID

        init(icon: String, text: String) {
            self.icon = icon
            self.text = text
            self.id = UUID()
        }

        static func == (lhs: ActionToast, rhs: ActionToast) -> Bool {
            lhs.id == rhs.id
        }
    }

    func show(icon: String, text: String, duration: TimeInterval = 3.0) {
        dismissTask?.cancel()
        currentToast = ActionToast(icon: icon, text: text)
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled {
                currentToast = nil
            }
        }
    }
}
