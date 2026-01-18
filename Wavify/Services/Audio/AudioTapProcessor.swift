//
//  AudioTapProcessor.swift
//  Wavify
//
//  MTAudioProcessingTap-based audio processor for applying real-time EQ to AVPlayer content
//

import Foundation
import AVFoundation
import MediaToolbox
import Combine

// MARK: - Tap Context

/// Context passed to MTAudioProcessingTap callbacks
/// Must be a class for reference semantics in C callbacks
final class AudioTapContext {
    /// The 10-band EQ processor
    let eqProcessor: TenBandEQProcessor
    
    /// Audio format info (populated in prepare callback)
    var sampleRate: Double = 44100
    var channelCount: Int = 2
    
    /// Flag to check if processor is valid
    var isValid: Bool = true
    
    init() {
        eqProcessor = TenBandEQProcessor()
    }
    
    deinit {
        isValid = false
    }
}

// MARK: - C-Style Tap Callbacks (Must be at file scope)

/// Called when the tap is initialized
private let tapInitCallback: MTAudioProcessingTapInitCallback = { (tap, clientInfo, tapStorageOut) in
    // Store the context pointer for later retrieval
    tapStorageOut.pointee = clientInfo
}

/// Called when the tap is finalized (deallocated)
private let tapFinalizeCallback: MTAudioProcessingTapFinalizeCallback = { (tap) in
    // Retrieve and release the context
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<AudioTapContext>.fromOpaque(storage).release()
}

/// Called when the tap is prepared for processing
private let tapPrepareCallback: MTAudioProcessingTapPrepareCallback = { (tap, maxFrames, processingFormat) in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<AudioTapContext>.fromOpaque(storage).takeUnretainedValue()
    
    // Store format info
    context.sampleRate = processingFormat.pointee.mSampleRate
    context.channelCount = Int(processingFormat.pointee.mChannelsPerFrame)
    
    // Reset filter states for new stream
    context.eqProcessor.reset()
}

/// Called when the tap is unprepared (stream ends)
private let tapUnprepareCallback: MTAudioProcessingTapUnprepareCallback = { (tap) in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<AudioTapContext>.fromOpaque(storage).takeUnretainedValue()
    context.eqProcessor.reset()
}

/// Main processing callback - called on audio render thread
/// CRITICAL: Must be fast, no blocking, no allocations
private let tapProcessCallback: MTAudioProcessingTapProcessCallback = { (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
    // Get source audio
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )
    
    guard status == noErr else { return }
    
    // Get context
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<AudioTapContext>.fromOpaque(storage).takeUnretainedValue()
    guard context.isValid else { return }
    
    // Process each audio buffer
    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    
    for buffer in bufferList {
        guard let data = buffer.mData else { continue }
        
        let floatBuffer = data.assumingMemoryBound(to: Float.self)
        let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / context.channelCount
        
        // Apply 10-band EQ
        context.eqProcessor.process(buffer: floatBuffer, frameCount: frameCount)
    }
}

// MARK: - Audio Tap Processor

/// Manages MTAudioProcessingTap for real-time audio EQ processing
@MainActor
final class AudioTapProcessor {
    
    // MARK: - Properties
    
    /// Shared context for tap callbacks
    private var tapContext: AudioTapContext?
    
    /// Reference to the current audio mix
    private var currentAudioMix: AVMutableAudioMix?
    
    /// Subscription to EQ settings changes
    private var settingsCancellable: AnyCancellable?
    
    /// Current sample rate (updated from tap prepare callback)
    private var currentSampleRate: Double = 44100
    
    // MARK: - Initialization
    
    init() {
        subscribeToEqualizerSettings()
    }
    
    deinit {
        settingsCancellable?.cancel()
    }
    
    // MARK: - Public API
    
    /// Attach audio processing tap to an AVPlayerItem
    /// - Parameter playerItem: The player item to process
    func attach(to playerItem: AVPlayerItem) {
        // Create new context for this player item
        let context = AudioTapContext()
        tapContext = context
        
        // Get audio tracks asynchronously
        let asset = playerItem.asset
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard let audioTrack = tracks.first else {
                    Logger.error("No audio track found in asset", category: .playback)
                    return
                }
                
                await MainActor.run {
                    createAndAttachTap(to: playerItem, audioTrack: audioTrack, context: context)
                }
            } catch {
                Logger.error("Failed to load audio tracks for EQ", category: .playback, error: error)
            }
        }
    }
    
    /// Detach and cleanup the audio tap
    func detach() {
        tapContext?.isValid = false
        tapContext = nil
        currentAudioMix = nil
    }
    
    /// Reset filter states (call on seek)
    func resetFilters() {
        tapContext?.eqProcessor.reset()
    }
    
    /// Update EQ settings
    func updateSettings(_ settings: EqualizerSettings) {
        guard let context = tapContext else { return }
        
        // Get gains (0 if disabled)
        let gains = settings.bands.map { settings.isEnabled ? $0.gain : Float(0) }
        
        // Calculate coefficients for current sample rate
        let bands = settings.bands.map { ($0.frequency, settings.isEnabled ? $0.gain : Float(0)) }
        let coefficients = BiquadCoefficientCalculator.calculateEQCoefficients(
            bands: bands,
            sampleRate: context.sampleRate
        )
        
        // Pass both coefficients and gains for auto-compensation
        context.eqProcessor.updateCoefficients(coefficients, gains: gains)
        
        Logger.log("EQ updated: \(settings.selectedPreset.rawValue), enabled: \(settings.isEnabled)", category: .playback)
    }
    
    // MARK: - Private Methods
    
    private func subscribeToEqualizerSettings() {
        settingsCancellable = EqualizerManager.shared.settingsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                Task { @MainActor in
                    self?.updateSettings(settings)
                }
            }
    }
    
    private func createAndAttachTap(
        to playerItem: AVPlayerItem,
        audioTrack: AVAssetTrack,
        context: AudioTapContext
    ) {
        // Create tap callbacks structure
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: tapInitCallback,
            finalize: tapFinalizeCallback,
            prepare: tapPrepareCallback,
            unprepare: tapUnprepareCallback,
            process: tapProcessCallback
        )
        
        // Create the audio processing tap
        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapRef
        )
        
        guard status == noErr, let tap = tapRef else {
            Logger.error("Failed to create MTAudioProcessingTap: \(status)", category: .playback)
            return
        }
        
        // Create audio mix with the tap
        let inputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParameters.audioTapProcessor = tap
        
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParameters]
        
        playerItem.audioMix = audioMix
        currentAudioMix = audioMix
        
        // Apply initial EQ settings
        updateSettings(EqualizerManager.shared.settings)
        
        Logger.log("MTAudioProcessingTap attached successfully", category: .playback)
    }
}
