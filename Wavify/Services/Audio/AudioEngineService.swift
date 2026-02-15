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
    private var sourceNodeB: AVAudioSourceNode!
    // Shared ring buffers — slot A (primary) and slot B (crossfade standby)
    // Capacity: 4 seconds @ 48kHz stereo (384k floats)
    let ringBuffer = CircularBuffer(capacity: 48000 * 2 * 4)
    let ringBufferB = CircularBuffer(capacity: 48000 * 2 * 4)

    // MARK: - Crossfade Routing

    enum ActiveSlot {
        case a, b
    }

    private(set) var activeSlot: ActiveSlot = .a
    private let volumeMixerA = AVAudioMixerNode()
    private let volumeMixerB = AVAudioMixerNode()
    private let crossfadeMixer = AVAudioMixerNode()

    /// The ring buffer currently used by the primary playback path
    var activeRingBuffer: CircularBuffer {
        activeSlot == .a ? ringBuffer : ringBufferB
    }

    /// The ring buffer used by the standby/incoming crossfade slot
    var standbyRingBuffer: CircularBuffer {
        activeSlot == .a ? ringBufferB : ringBuffer
    }

    // MARK: - Stem Crossfade Routing (Premium)

    // 8 stem source nodes (4 per track slot: drums, bass, vocal, atmosphere)
    private var stemSrcA_drums: AVAudioSourceNode!
    private var stemSrcA_bass: AVAudioSourceNode!
    private var stemSrcA_vocal: AVAudioSourceNode!
    private var stemSrcA_atmos: AVAudioSourceNode!
    private var stemSrcB_drums: AVAudioSourceNode!
    private var stemSrcB_bass: AVAudioSourceNode!
    private var stemSrcB_vocal: AVAudioSourceNode!
    private var stemSrcB_atmos: AVAudioSourceNode!

    // 8 volume mixers for individual stem control
    private let stemVolA_drums = AVAudioMixerNode()
    private let stemVolA_bass = AVAudioMixerNode()
    private let stemVolA_vocal = AVAudioMixerNode()
    private let stemVolA_atmos = AVAudioMixerNode()
    private let stemVolB_drums = AVAudioMixerNode()
    private let stemVolB_bass = AVAudioMixerNode()
    private let stemVolB_vocal = AVAudioMixerNode()
    private let stemVolB_atmos = AVAudioMixerNode()

    // Stem mixer collects all 8 stems → crossfadeMixer
    private let stemMixer = AVAudioMixerNode()

    // Stem ring buffers — smaller capacity (~2s @ 44100Hz stereo)
    let stemBufferA_drums = CircularBuffer(capacity: 44100 * 2 * 2)
    let stemBufferA_bass = CircularBuffer(capacity: 44100 * 2 * 2)
    let stemBufferA_vocal = CircularBuffer(capacity: 44100 * 2 * 2)
    let stemBufferA_atmos = CircularBuffer(capacity: 44100 * 2 * 2)
    let stemBufferB_drums = CircularBuffer(capacity: 44100 * 2 * 2)
    let stemBufferB_bass = CircularBuffer(capacity: 44100 * 2 * 2)
    let stemBufferB_vocal = CircularBuffer(capacity: 44100 * 2 * 2)
    let stemBufferB_atmos = CircularBuffer(capacity: 44100 * 2 * 2)

    /// Whether stem mode is currently active
    private(set) var isStemModeActive = false

    /// Get the stem ring buffers for the active slot
    var activeStemBuffers: (drums: CircularBuffer, bass: CircularBuffer, vocal: CircularBuffer, atmos: CircularBuffer) {
        activeSlot == .a
            ? (stemBufferA_drums, stemBufferA_bass, stemBufferA_vocal, stemBufferA_atmos)
            : (stemBufferB_drums, stemBufferB_bass, stemBufferB_vocal, stemBufferB_atmos)
    }

    /// Get the stem ring buffers for the standby slot
    var standbyStemBuffers: (drums: CircularBuffer, bass: CircularBuffer, vocal: CircularBuffer, atmos: CircularBuffer) {
        activeSlot == .a
            ? (stemBufferB_drums, stemBufferB_bass, stemBufferB_vocal, stemBufferB_atmos)
            : (stemBufferA_drums, stemBufferA_bass, stemBufferA_vocal, stemBufferA_atmos)
    }

    // MARK: - DSP Nodes

    // Converter Node (Critical for Resampling)
    // crossfadeMixer -> inputMixer -> Rest of Graph
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

    /// Creates an AVAudioSourceNode that reads from the given ring buffer
    private func makeSourceNode(for buffer: CircularBuffer) -> AVAudioSourceNode {
        AVAudioSourceNode { [weak buffer] _, _, frameCount, audioBufferList in
            guard let ringBuffer = buffer else { return noErr }

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let totalSamples = Int(frameCount) * 2

            var tempBuffer = [Float](repeating: 0, count: totalSamples)

            let samplesRead = tempBuffer.withUnsafeMutableBufferPointer { ptr in
                return ringBuffer.read(into: ptr.baseAddress!, count: totalSamples)
            }

            if samplesRead == 0 {
                for buffer in buffers {
                    memset(buffer.mData, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }

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

    private func createSourceNode() {
        sourceNode = makeSourceNode(for: ringBuffer)
        sourceNodeB = makeSourceNode(for: ringBufferB)

        // Stem source nodes (4 per slot: drums, bass, vocal, atmosphere)
        stemSrcA_drums = makeSourceNode(for: stemBufferA_drums)
        stemSrcA_bass = makeSourceNode(for: stemBufferA_bass)
        stemSrcA_vocal = makeSourceNode(for: stemBufferA_vocal)
        stemSrcA_atmos = makeSourceNode(for: stemBufferA_atmos)
        stemSrcB_drums = makeSourceNode(for: stemBufferB_drums)
        stemSrcB_bass = makeSourceNode(for: stemBufferB_bass)
        stemSrcB_vocal = makeSourceNode(for: stemBufferB_vocal)
        stemSrcB_atmos = makeSourceNode(for: stemBufferB_atmos)
    }

    private func setupGraph() {
        // Attach normal path nodes
        engine.attach(sourceNode)
        engine.attach(sourceNodeB)
        engine.attach(volumeMixerA)
        engine.attach(volumeMixerB)
        engine.attach(crossfadeMixer)
        engine.attach(inputMixer) // Resampler
        engine.attach(mainEQ)
        engine.attach(bassEQ)
        engine.attach(bassDistortion)
        engine.attach(bassMixer)
        engine.attach(compressor)
        engine.attach(limiter)
        engine.attach(mainMixer)
        engine.attach(outputMixer)

        // Attach stem path nodes (all pre-connected, silent when inactive)
        engine.attach(stemSrcA_drums)
        engine.attach(stemSrcA_bass)
        engine.attach(stemSrcA_vocal)
        engine.attach(stemSrcA_atmos)
        engine.attach(stemSrcB_drums)
        engine.attach(stemSrcB_bass)
        engine.attach(stemSrcB_vocal)
        engine.attach(stemSrcB_atmos)
        engine.attach(stemVolA_drums)
        engine.attach(stemVolA_bass)
        engine.attach(stemVolA_vocal)
        engine.attach(stemVolA_atmos)
        engine.attach(stemVolB_drums)
        engine.attach(stemVolB_bass)
        engine.attach(stemVolB_vocal)
        engine.attach(stemVolB_atmos)
        engine.attach(stemMixer)

        // Format: Standard float32 stereo
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)

        // Source nodes are locked at 44100Hz stereo — SRC happens in the tap callback
        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)

        // --- Normal Routing Graph ---
        //
        // sourceNode  -> volumeMixerA ──┐
        // sourceNodeB -> volumeMixerB ──┤
        //                                ├→ crossfadeMixer -> inputMixer -> [EQ chain]
        //                    STEM PATH   │
        // stemSrc_A_drums -> stemVol_A_drums ──┐
        // stemSrc_A_bass  -> stemVol_A_bass  ──┤
        // stemSrc_A_vocal -> stemVol_A_vocal ──┤
        // stemSrc_A_atmos -> stemVol_A_atmos ──┤
        //                                      ├→ stemMixer ──→ crossfadeMixer
        // stemSrc_B_drums -> stemVol_B_drums ──┤
        // stemSrc_B_bass  -> stemVol_B_bass  ──┤
        // stemSrc_B_vocal -> stemVol_B_vocal ──┤
        // stemSrc_B_atmos -> stemVol_B_atmos ──┘

        // 1. Normal source nodes -> Volume mixers (locked at 44100Hz)
        engine.connect(sourceNode, to: volumeMixerA, format: sourceFormat)
        engine.connect(sourceNodeB, to: volumeMixerB, format: sourceFormat)

        // 2. Volume mixers -> Crossfade mixer
        engine.connect(volumeMixerA, to: crossfadeMixer, format: outputFormat)
        engine.connect(volumeMixerB, to: crossfadeMixer, format: outputFormat)

        // 3. Stem source nodes -> Stem volume mixers (locked at 44100Hz)
        engine.connect(stemSrcA_drums, to: stemVolA_drums, format: sourceFormat)
        engine.connect(stemSrcA_bass, to: stemVolA_bass, format: sourceFormat)
        engine.connect(stemSrcA_vocal, to: stemVolA_vocal, format: sourceFormat)
        engine.connect(stemSrcA_atmos, to: stemVolA_atmos, format: sourceFormat)
        engine.connect(stemSrcB_drums, to: stemVolB_drums, format: sourceFormat)
        engine.connect(stemSrcB_bass, to: stemVolB_bass, format: sourceFormat)
        engine.connect(stemSrcB_vocal, to: stemVolB_vocal, format: sourceFormat)
        engine.connect(stemSrcB_atmos, to: stemVolB_atmos, format: sourceFormat)

        // 4. Stem volume mixers -> Stem mixer
        engine.connect(stemVolA_drums, to: stemMixer, format: outputFormat)
        engine.connect(stemVolA_bass, to: stemMixer, format: outputFormat)
        engine.connect(stemVolA_vocal, to: stemMixer, format: outputFormat)
        engine.connect(stemVolA_atmos, to: stemMixer, format: outputFormat)
        engine.connect(stemVolB_drums, to: stemMixer, format: outputFormat)
        engine.connect(stemVolB_bass, to: stemMixer, format: outputFormat)
        engine.connect(stemVolB_vocal, to: stemMixer, format: outputFormat)
        engine.connect(stemVolB_atmos, to: stemMixer, format: outputFormat)

        // 5. Stem mixer -> Crossfade mixer
        engine.connect(stemMixer, to: crossfadeMixer, format: outputFormat)

        // 6. Crossfade mixer -> InputMixer (Handles Resampling)
        engine.connect(crossfadeMixer, to: inputMixer, format: outputFormat)

        // 4. InputMixer -> Split to EQ Paths (Using Output Format)
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

        // Initial crossfade volumes
        volumeMixerA.outputVolume = 1.0
        volumeMixerB.outputVolume = 0.0

        // All stem volumes start at 0 (silent until premium transition)
        stemVolA_drums.outputVolume = 0.0
        stemVolA_bass.outputVolume = 0.0
        stemVolA_vocal.outputVolume = 0.0
        stemVolA_atmos.outputVolume = 0.0
        stemVolB_drums.outputVolume = 0.0
        stemVolB_bass.outputVolume = 0.0
        stemVolB_vocal.outputVolume = 0.0
        stemVolB_atmos.outputVolume = 0.0

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
        activeRingBuffer.clear()
    }

    /// Flush only the standby ring buffer (used after crossfade completes)
    func flushStandby() {
        standbyRingBuffer.clear()
    }

    // MARK: - Crossfade Volume Control

    /// Set crossfade volumes based on active slot. outGain applies to outgoing, inGain to incoming.
    func setCrossfadeVolumes(outGain: Float, inGain: Float) {
        switch activeSlot {
        case .a:
            volumeMixerA.outputVolume = outGain
            volumeMixerB.outputVolume = inGain
        case .b:
            volumeMixerB.outputVolume = outGain
            volumeMixerA.outputVolume = inGain
        }
    }

    /// Reset to single-track mode: active mixer at 1.0, standby at 0.0
    func resetToSingleTrack() {
        switch activeSlot {
        case .a:
            volumeMixerA.outputVolume = 1.0
            volumeMixerB.outputVolume = 0.0
        case .b:
            volumeMixerB.outputVolume = 1.0
            volumeMixerA.outputVolume = 0.0
        }
    }

    /// Swap which slot is considered active (called after crossfade completes)
    func swapActiveSlot() {
        activeSlot = activeSlot == .a ? .b : .a
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

    // MARK: - Stem Crossfade Control

    /// Set individual stem volumes during a premium transition.
    /// Called by TransitionChoreographer at 60Hz.
    func setStemVolumes(_ volumes: TransitionChoreographer.StemVolumes) {
        switch activeSlot {
        case .a:
            // A is outgoing, B is incoming
            stemVolA_drums.outputVolume = volumes.outDrums
            stemVolA_bass.outputVolume = volumes.outBass
            stemVolA_vocal.outputVolume = volumes.outVocal
            stemVolA_atmos.outputVolume = volumes.outAtmosphere
            stemVolB_drums.outputVolume = volumes.inDrums
            stemVolB_bass.outputVolume = volumes.inBass
            stemVolB_vocal.outputVolume = volumes.inVocal
            stemVolB_atmos.outputVolume = volumes.inAtmosphere
        case .b:
            // B is outgoing, A is incoming
            stemVolB_drums.outputVolume = volumes.outDrums
            stemVolB_bass.outputVolume = volumes.outBass
            stemVolB_vocal.outputVolume = volumes.outVocal
            stemVolB_atmos.outputVolume = volumes.outAtmosphere
            stemVolA_drums.outputVolume = volumes.inDrums
            stemVolA_bass.outputVolume = volumes.inBass
            stemVolA_vocal.outputVolume = volumes.inVocal
            stemVolA_atmos.outputVolume = volumes.inAtmosphere
        }
    }

    /// Timer for stem mode ramp transitions
    private var stemRampTimer: DispatchSourceTimer?

    /// Activate stem mode: 50ms equal-power ramp from normal mixers to stems
    func activateStemMode() {
        isStemModeActive = true
        stemRampTimer?.cancel()

        let steps = 50
        var step = 0
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            step += 1
            let progress = Float(step) / Float(steps)
            // Equal-power ramp: normal down via cos, stems come up via choreographer
            let normalGain = cos(progress * .pi / 2)
            self.volumeMixerA.outputVolume = normalGain
            self.volumeMixerB.outputVolume = normalGain
            if step >= steps {
                self.volumeMixerA.outputVolume = 0.0
                self.volumeMixerB.outputVolume = 0.0
                self.stemRampTimer?.cancel()
                self.stemRampTimer = nil
            }
        }
        timer.resume()
        stemRampTimer = timer
    }

    /// Deactivate stem mode: 50ms ramp from stems back to normal mixers
    func deactivateStemMode() {
        stemRampTimer?.cancel()

        // Capture current stem volumes to ramp from
        let initAD = stemVolA_drums.outputVolume
        let initAB = stemVolA_bass.outputVolume
        let initAV = stemVolA_vocal.outputVolume
        let initAA = stemVolA_atmos.outputVolume
        let initBD = stemVolB_drums.outputVolume
        let initBB = stemVolB_bass.outputVolume
        let initBV = stemVolB_vocal.outputVolume
        let initBA = stemVolB_atmos.outputVolume

        let steps = 50
        var step = 0
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            step += 1
            let progress = Float(step) / Float(steps)
            // Ramp normal mixers back up
            let normalGain = sin(progress * .pi / 2)
            // Stems ramp down with absolute scaling from initial values
            let stemScale = cos(progress * .pi / 2)

            self.volumeMixerA.outputVolume = normalGain
            self.volumeMixerB.outputVolume = normalGain

            self.stemVolA_drums.outputVolume = initAD * stemScale
            self.stemVolA_bass.outputVolume = initAB * stemScale
            self.stemVolA_vocal.outputVolume = initAV * stemScale
            self.stemVolA_atmos.outputVolume = initAA * stemScale
            self.stemVolB_drums.outputVolume = initBD * stemScale
            self.stemVolB_bass.outputVolume = initBB * stemScale
            self.stemVolB_vocal.outputVolume = initBV * stemScale
            self.stemVolB_atmos.outputVolume = initBA * stemScale

            if step >= steps {
                self.isStemModeActive = false
                // Silence all stems
                self.stemVolA_drums.outputVolume = 0.0
                self.stemVolA_bass.outputVolume = 0.0
                self.stemVolA_vocal.outputVolume = 0.0
                self.stemVolA_atmos.outputVolume = 0.0
                self.stemVolB_drums.outputVolume = 0.0
                self.stemVolB_bass.outputVolume = 0.0
                self.stemVolB_vocal.outputVolume = 0.0
                self.stemVolB_atmos.outputVolume = 0.0

                // Clear stem ring buffers
                self.stemBufferA_drums.clear()
                self.stemBufferA_bass.clear()
                self.stemBufferA_vocal.clear()
                self.stemBufferA_atmos.clear()
                self.stemBufferB_drums.clear()
                self.stemBufferB_bass.clear()
                self.stemBufferB_vocal.clear()
                self.stemBufferB_atmos.clear()

                // Restore normal routing
                self.resetToSingleTrack()

                self.stemRampTimer?.cancel()
                self.stemRampTimer = nil
            }
        }
        timer.resume()
        stemRampTimer = timer
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
