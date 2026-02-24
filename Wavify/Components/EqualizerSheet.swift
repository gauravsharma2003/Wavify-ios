//
//  EqualizerSheet.swift
//  Wavify
//
//  Audio equalizer bottom sheet with presets and custom band controls
//

import SwiftUI

struct EqualizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var equalizerManager = EqualizerManager.shared
    @State private var localSettings: EqualizerSettings
    @State private var hasChanges = false
    
    init() {
        _localSettings = State(initialValue: EqualizerManager.shared.settings)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            
            // Preset selector
            presetSelector
            
            Spacer()
            
            // EQ Bands - centered between chips and reset button
            equalizerBands
                .padding(.horizontal, 16)
            
            Spacer()
            
            // Bottom buttons
            bottomButtons
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
        }
        .background(
            Color(white: 0.06)
                .ignoresSafeArea()
        )
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            // Cancel button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.interactive())
            
            Spacer()
            
            Text("Equalizer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            
            Spacer()
            
            // On/Off toggle removed as per request (always enabled if sheet is open, or managed implicitly)
            // If user wants to "remove on off button", we assume they want it always active?
            // Actually, "selecting any mode or customizing" implies it's active.
            // We'll keep the variable but remove the UI control.
            // Or better, we explicitly set enabled = true when they interact.
            
            // For UI, just Spacer() to keep title centered if we want, or just Remove the toggle button
            // But we need to balance the "X" button on left.
            // Let's add an empty frame of same size to keep title centered.
            Color.clear.frame(width: 40, height: 40)
        }
    }
    
    // MARK: - Preset Selector

    private var presetSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(EqualizerPreset.allCases.filter { $0 != .custom }) { preset in
                    let isSelected = localSettings.selectedPreset == preset

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localSettings.applyPreset(preset)
                            localSettings.isEnabled = true
                            applySettingsInternal()
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(preset.rawValue)
                                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))

                            Rectangle()
                                .fill(isSelected ? .white : .clear)
                                .frame(height: 2)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.horizontal, 6)
        }
    }
    
    // MARK: - Equalizer Bands
    
    private var equalizerBands: some View {
        HStack(spacing: 8) {
            ForEach(localSettings.bands.indices, id: \.self) { index in
                BandSlider(
                    band: $localSettings.bands[index],
                    isEnabled: localSettings.isEnabled
                ) {
                    // When user adjusts slider, switch to custom and apply immediately
                    if localSettings.selectedPreset != .custom {
                        localSettings.selectedPreset = .custom
                    }
                    localSettings.isEnabled = true
                    applySettingsInternal()
                }
            }
        }
        .frame(height: 160)
    }
    
    // MARK: - Bottom Buttons
    
    private var bottomButtons: some View {
        // Reset button - fully expanded
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                localSettings.reset()
                localSettings.isEnabled = true // Reset implies active flat
                applySettingsInternal()
            }
        } label: {
            Text("Reset")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
    
    // Internal apply helper
    private func applySettingsInternal() {
        // Apply all band gains
        for (index, band) in localSettings.bands.enumerated() {
            EqualizerManager.shared.updateBandGain(at: index, gain: band.gain)
        }
        
        // Apply preset
        if localSettings.selectedPreset != .custom {
            EqualizerManager.shared.applyPreset(localSettings.selectedPreset)
        }
        
        EqualizerManager.shared.setEnabled(localSettings.isEnabled)
        EqualizerManager.shared.save()
    }
    
    // MARK: - Actions
    
    // Old save method removed in flavor of auto-save
}


// MARK: - Band Slider

private struct BandSlider: View {
    @Binding var band: EqualizerBand
    let isEnabled: Bool
    let onChange: () -> Void
    
    private let sliderHeight: CGFloat = 120
    
    var body: some View {
        VStack(spacing: 4) {
            // dB value
            Text(String(format: "%+.0f", band.gain))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(isEnabled ? .white : .white.opacity(0.4))
                .frame(height: 14)
            
            // Native vertical slider (rotated)
            Slider(
                value: Binding(
                    get: { Double(band.gain) },
                    set: { newValue in
                        band.gain = Float(newValue)
                        onChange()
                    }
                ),
                in: -12...12
            )
            .tint(.cyan)
            .rotationEffect(.degrees(-90))
            .frame(width: sliderHeight, height: 28)
            .frame(width: 28, height: sliderHeight)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
            
            // Frequency label
            Text(band.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .opacity(isEnabled ? 1 : 0.5)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        EqualizerSheet()
    }
}
