//
//  AirPlayRoutePickerView.swift
//  Wavify
//
//  Created by Auto-Agent on 02/01/26.
//

import SwiftUI
import AVKit

struct AirPlayRoutePickerView: UIViewRepresentable {
    @Binding var showPicker: Bool
    
    init(showPicker: Binding<Bool> = .constant(false)) {
        self._showPicker = showPicker
    }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = .white
        routePickerView.tintColor = .white
        routePickerView.backgroundColor = .clear
        routePickerView.prioritizesVideoDevices = false
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        if showPicker {
            // Recursively find the button and trigger it
            if let button = findButton(in: uiView) {
                button.sendActions(for: .touchUpInside)
            }
            
            // Reset state immediately
            DispatchQueue.main.async {
                showPicker = false
            }
        }
    }
    
    private func findButton(in view: UIView) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton {
                return button
            }
            if let found = findButton(in: subview) {
                return found
            }
        }
        return nil
    }
}
