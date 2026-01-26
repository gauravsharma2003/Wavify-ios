//
//  AudioEngineService.swift
//  Wavify
//
//  Manages the AVAudioEngine graph for high-fidelity audio processing.
//  Receives audio from CircularBuffer and applies:
//  1. Parametric EQ (10-band, mapped from UI)
//  2. Parallel Bass Enhancement (Psychoacoustic)
//  3. Compression
//  4. Limiting
//

import Foundation
import AVFoundation
import Accelerate
import Combine

/// Manages the high-fidelity audio processing pipeline
@MainActor
class AudioEngineService: ObservableObject {
    
    static let shared = AudioEngineService()
    
    // MARK: - Core Components
    
    let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var sourceFormat: AVAudioFormat?
    
    // Shared ring buffer to receive data from AVPlayer tap
    // Capacity: 4 seconds @ 48kHz stereo (384k floats) - extra headroom for network fluctuations
    let ringBuffer = CircularBuffer(capacity: 48000 * 2 * 4)
    
    // MARK: - DSP Nodes
    
    // Converter Node (Critical for Resampling)
    // Source -> inputMixer -> Rest of Graph
    private let inputMixer = AVAudioMixerNode()
    
    // Main signal path - 10 bands to match UI sliders
    private let mainEQ = AVAudioUnitEQ(numberOfBands: 10)
    private let mainMixer = AVAudioMixerNode()
    
    // Parallel Bass path
    private let bassEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let bassDistortion = AVAudioUnitDistortion()
    private let bassMixer = AVAudioMixerNode()
    
    // Dynamics
    private let compressor = AVAudioUnitDynamicsProcessor()
    private let limiter = AVAudioUnitDynamicsProcessor()
    
    // Output
    private let outputMixer = AVAudioMixerNode()
    
    // MARK: - Integration
    
    private var settingsCancellable: AnyCancellable?
    
    // MARK: - Adaptive Bass State

    private var isAdaptiveBassEnabled = true
    private var lastRms: Float = 0
    private var adaptiveBassTimer: Timer?

    // MARK: - Initialization State

    /// Whether the audio engine graph has been fully set up
    private var isInitialized = false

    /// Continuation for callers waiting on initialization
    private var initializationContinuations: [CheckedContinuation<Void, Never>] = []
    private let initLock = NSLock()

    // MARK: - Initialization

    init() {
        // Defer heavy setup to background to avoid main thread blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.createSourceNode()
            self?.setupGraph()

            // Mark as initialized and resume any waiting callers
            self?.initLock.lock()
            self?.isInitialized = true
            let continuations = self?.initializationContinuations ?? []
            self?.initializationContinuations.removeAll()
            self?.initLock.unlock()

            for continuation in continuations {
                continuation.resume()
            }

            DispatchQueue.main.async {
                self?.subscribeToEqualizerSettings()
            }
        }
    }

    /// Wait for the audio engine to be fully initialized
    /// Returns immediately if already initialized
    func waitForInitialization() async {
        initLock.lock()
        if isInitialized {
            initLock.unlock()
            return
        }
        initLock.unlock()

        await withCheckedContinuation { continuation in
            initLock.lock()
            // Double-check after acquiring lock
            if isInitialized {
                initLock.unlock()
                continuation.resume()
                return
            }
            initializationContinuations.append(continuation)
            initLock.unlock()
        }
    }

    /// Whether the engine is ready to use
    var isReady: Bool {
        initLock.lock()
        defer { initLock.unlock() }
        return isInitialized
    }
    
    private func createSourceNode() {
        // Create source node to read from ring buffer
        sourceNode = AVAudioSourceNode { [weak ringBuffer = ringBuffer] _, _, frameCount, audioBufferList in
            guard let ringBuffer = ringBuffer else { return noErr }

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let totalSamples = Int(frameCount) * 2

            // Temporary buffer for interleaved read
            var tempBuffer = [Float](repeating: 0, count: totalSamples)

            let samplesRead = tempBuffer.withUnsafeMutableBufferPointer { ptr in
                return ringBuffer.read(into: ptr.baseAddress!, count: totalSamples)
            }

            if samplesRead == 0 {
                // Silence
                for buffer in buffers {
                    memset(buffer.mData, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }

            // De-interleave into output buffers
            if let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
               let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {

                for i in 0..<Int(frameCount) {
                    if i * 2 + 1 < samplesRead {
                        left[i] = tempBuffer[i * 2]
                        right[i] = tempBuffer[i * 2 + 1]
                    } else {
                        left[i] = 0
                        right[i] = 0
                    }
                }
            }

            return noErr
        }
    }
    
    /// Reconfigures the source node format. Must be called when AVPlayer format changes.
    func reconfigure(sampleRate: Double, channels: Int) {
        let newFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))
        
        // Only reconfigure if format changed
        if let current = sourceFormat,
           current.sampleRate == sampleRate,
           current.channelCount == channels {
            return
        }
        
        Logger.log("Reconfiguring Audio Engine for \(sampleRate)Hz \(channels)ch", category: .playback)
        
        // Must stop engine to reconfigure connections
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        
        sourceFormat = newFormat
        
        // Reconnect source node -> inputMixer with new format
        // inputMixer handles the resampling to the graph format
        engine.disconnectNodeOutput(sourceNode)
        engine.connect(sourceNode, to: inputMixer, format: newFormat)
        
        if wasRunning {
            start()
        }
    }
    
    private func setupGraph() {
        // Attach nodes
        engine.attach(sourceNode)
        engine.attach(inputMixer) // Resampler
        engine.attach(mainEQ)
        engine.attach(bassEQ)
        engine.attach(bassDistortion)
        engine.attach(bassMixer)
        engine.attach(compressor)
        engine.attach(limiter)
        engine.attach(mainMixer)
        engine.attach(outputMixer)
        
        // Format: Standard float32 stereo
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        
        // Initial defaults (will be updated by reconfigure)
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        sourceFormat = defaultFormat
        
        // --- Routing Graph ---
        //
        // Source(Var) -> InputMixer(Resampler) -> [MainEQ, BassEQ] -> ...
        
        // 1. Source -> InputMixer (Handles Format Conversion)
        engine.connect(sourceNode, to: inputMixer, format: defaultFormat)
        
        // 2. InputMixer -> Split to EQ Paths (Using Output Format)
        let points = [
            AVAudioConnectionPoint(node: mainEQ, bus: 0),
            AVAudioConnectionPoint(node: bassEQ, bus: 0)
        ]
        engine.connect(inputMixer, to: points, fromBus: 0, format: outputFormat)
        
        // Parallel Bass Chain
        engine.connect(bassEQ, to: bassDistortion, format: outputFormat)
        engine.connect(bassDistortion, to: bassMixer, format: outputFormat)
        
        // Main Chain
        engine.connect(mainEQ, to: mainMixer, format: outputFormat)
        
        // Merge Bass into Main
        engine.connect(bassMixer, to: mainMixer, format: outputFormat)
        
        // Dynamics Chain
        engine.connect(mainMixer, to: compressor, format: outputFormat)
        engine.connect(compressor, to: limiter, format: outputFormat)
        engine.connect(limiter, to: engine.mainMixerNode, format: outputFormat)
        
        configureNodes()
    }
    
    private func configureNodes() {
        // --- 1. Main EQ Initial Setup (Flat) ---
        let standardFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        
        for (i, freq) in standardFrequencies.enumerated() {
            let band = mainEQ.bands[i]
            band.frequency = freq
            band.bypass = false // Active but 0 gain initially
            band.gain = 0
            
            // Band types matching standard graphic EQ behavior
            if i == 0 {
                band.filterType = .lowShelf
            } else if i == standardFrequencies.count - 1 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
                band.bandwidth = 1.0 // Standard Q
            }
        }
        
        // --- 2. Bass Path Setup ---
        // Band 0: Low Pass to isolate bass (cutoff 120Hz)
        bassEQ.bands[0].filterType = .lowPass
        bassEQ.bands[0].frequency = 120
        bassEQ.bands[0].bypass = false
        
        // Band 1: Boost for harmonics input
        bassEQ.bands[1].filterType = .lowShelf
        bassEQ.bands[1].frequency = 60
        bassEQ.bands[1].gain = 0 // Adaptive/Preset will control this
        bassEQ.bands[1].bypass = false
        
        // Harmonic Generation (Distortion)
        bassDistortion.loadFactoryPreset(.multiCellphoneConcert)
        bassDistortion.preGain = -6
        bassDistortion.wetDryMix = 20
        
        // --- 3. Compressor (Vocal Protection) ---
        compressor.threshold = -18
        compressor.headRoom = 6
        compressor.expansionRatio = 1
        compressor.attackTime = 0.002
        compressor.releaseTime = 0.08
        compressor.masterGain = 0
        
        // --- 4. Limiter (Safety) ---
        limiter.threshold = -2.0
        limiter.headRoom = 1.0
        limiter.expansionRatio = 1
        limiter.attackTime = 0.001
        limiter.releaseTime = 0.05
        limiter.masterGain = 0
        
        // --- 5. Mix Levels ---
        mainMixer.outputVolume = 1.0
        bassMixer.outputVolume = 0.0
        
        // Update with current settings (if any)
        updateSettings(EqualizerManager.shared.settings)
    }
    
    // MARK: - Lifecycle Management
    
    func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            
            startAdaptiveBassMonitoring()
        } catch {
            Logger.error("Failed to start AudioEngine", category: .playback, error: error)
        }
    }
    
    func stop() {
        engine.stop()
        stopAdaptiveBassMonitoring()
    }
    
    func flush() {
        ringBuffer.clear()
    }

    /// Mute audio output (used during song transitions to prevent glitchy sounds)
    /// Mutes at the final output stage to silence any audio buffered in intermediate nodes
    func mute() {
        engine.mainMixerNode.outputVolume = 0
    }

    /// Unmute audio output
    func unmute() {
        engine.mainMixerNode.outputVolume = 1
    }

    // MARK: - Settings Updates
    
    private func subscribeToEqualizerSettings() {
        settingsCancellable = EqualizerManager.shared.settingsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.updateSettings(settings)
            }
    }
    
    func updateSettings(_ settings: EqualizerSettings) {
        guard settings.isEnabled else {
            // Bypass all
            for band in mainEQ.bands { band.gain = 0 }
            bassMixer.outputVolume = 0
            return
        }
        
        // 1. Apply UI gains to Main EQ
        // Safely map up to available bands
        for (i, bandSetting) in settings.bands.enumerated() {
            guard i < mainEQ.bands.count else { break }
            mainEQ.bands[i].gain = bandSetting.gain
        }
        
        // 2. Intelligent Bass Processing
        // Analyze low end gains (32Hz, 64Hz, 125Hz)
        let lowEndGain = (settings.bands[0].gain + settings.bands[1].gain) / 2.0
        
        if lowEndGain > 3.0 || settings.selectedPreset == .megaBass {
            // High bass requested -> Engage Parallel Bass
            bassMixer.outputVolume = 0.25 // 25% mix
            bassEQ.bands[1].gain = 6.0 // Drive harmonics
            
            // Compensate Main EQ to avoid mud (don't double boost)
            // If user asked for +4dB, the parallel path adds perceived bass.
            // We can slightly reduce the direct low shelf to keep it clean.
             mainEQ.bands[0].gain = min(mainEQ.bands[0].gain, 4.0) // Cap main bass boost
        } else {
            // Normal bass
            bassMixer.outputVolume = 0.05 // Subtle warmth
            bassEQ.bands[1].gain = 0
        }
        
        
    }
    
    // MARK: - Adaptive Bass Logic
    
    private func startAdaptiveBassMonitoring() {
        // Placeholder for future adaptive logic
    }
    
    private func stopAdaptiveBassMonitoring() {
        adaptiveBassTimer?.invalidate()
        adaptiveBassTimer = nil
    }
}
