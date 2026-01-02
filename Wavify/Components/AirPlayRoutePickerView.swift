//
//  AirPlayRoutePickerView.swift
//  Wavify
//
//  Created by Auto-Agent on 02/01/26.
//

import SwiftUI
import AVKit

struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = .white
        routePickerView.tintColor = .white
        
        // This makes the button look like a standard system button unless customized further
        // but the user asked to "change the icon to white matching the design".
        // AVRoutePickerView handles its own icon.
        // We can force the tint color.
        
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // No updates needed currently
    }
}
