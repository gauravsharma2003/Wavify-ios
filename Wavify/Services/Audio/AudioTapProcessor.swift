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

    /// Task for async tap attachment - allows cancellation
    private var attachTask: Task<Void, Never>?

    /// Unique ID to track which attachment is current
    private var currentAttachmentId: UUID?

    // MARK: - Initialization

    init() {
        subscribeToEqualizerSettings()
    }

    deinit {
        settingsCancellable?.cancel()
        attachTask?.cancel()
    }

    // MARK: - Public API

    /// Attach audio processing tap to an AVPlayerItem synchronously
    /// Called when player is readyToPlay, so tracks should be available
    /// - Parameter playerItem: The player item to process
    func attachSync(to playerItem: AVPlayerItem) {
        // Cancel any pending attachment task
        attachTask?.cancel()

        // DON'T invalidate previous context here - its tap may still be processing
        // The old tap will finalize naturally when the old playerItem is deallocated

        // Create new context for this player item
        let context = AudioTapContext()
        tapContext = context

        let attachmentId = UUID()
        currentAttachmentId = attachmentId

        let asset = playerItem.asset

        // Use synchronous tracks access - fast when asset is ready
        let tracks = asset.tracks(withMediaType: .audio)

        guard let audioTrack = tracks.first else {
            // Fallback to async if sync fails
            attachTask = Task {
                do {
                    let asyncTracks = try await asset.loadTracks(withMediaType: .audio)
                    guard self.currentAttachmentId == attachmentId else { return }
                    if let track = asyncTracks.first {
                        self.createAndAttachTap(to: playerItem, audioTrack: track, context: context)
                    }
                } catch {
                    Logger.error("Failed to load audio tracks for EQ", category: .playback, error: error)
                }
            }
            return
        }

        createAndAttachTap(to: playerItem, audioTrack: audioTrack, context: context)
    }

    /// Attach audio processing tap to an AVPlayerItem (async fire-and-forget version)
    /// - Parameter playerItem: The player item to process
    func attach(to playerItem: AVPlayerItem) {
        // Just call the sync version directly
        attachSync(to: playerItem)
    }

    /// Detach and cleanup the audio tap
    func detach() {
        // Cancel any pending attachment
        attachTask?.cancel()
        attachTask = nil
        currentAttachmentId = nil

        // DON'T invalidate context here - the tap may still be processing audio
        // Let it finalize naturally via tapFinalizeCallback when audio engine releases it
        // The audioMix should be cleared on playerItem BEFORE calling this method
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
        

    }
}
