//
//  AudioTapProcessor.swift
//  Wavify
//
//  MTAudioProcessingTap-based audio processor.
//  Acts as a bridge: Captures audio from AVPlayer (streaming) and writes it to the CircularBuffer.
//  Crucially, it SILENCES the pass-through audio so AVPlayer doesn't play raw sound.
//
//  Source nodes are locked at 44100Hz. If the source track has a different sample rate,
//  linear-interpolation SRC is performed in the tap callback (zero engine restarts).
//

import Foundation
import AVFoundation
import MediaToolbox
import Combine
import Accelerate

// MARK: - Tap Context

/// Context passed to MTAudioProcessingTap callbacks
final class AudioTapContext {
    var sampleRate: Double = 44100
    var channelCount: Int = 2
    var isValid: Bool = true

    // Direct reference to the ring buffer for synchronous access
    let ringBuffer: CircularBuffer

    // Pre-allocated buffer to avoid runtime allocations in real-time callback
    // Use UnsafeMutablePointer for true zero-copy access
    private var interleavedBuffer: UnsafeMutablePointer<Float>?
    private var bufferCapacity: Int = 0

    // MARK: - SRC (Sample Rate Conversion)

    /// Whether this source needs resampling to 44100Hz
    private(set) var needsSRC: Bool = false
    /// Ratio: sourceSampleRate / 44100.0
    private var srcRatio: Double = 1.0
    /// Phase accumulator for linear interpolation across block boundaries
    private var srcPhase: Double = 0.0
    /// Previous last samples for cross-block interpolation
    private var prevSampleLeft: Float = 0
    private var prevSampleRight: Float = 0
    /// Pre-allocated resampled output buffers
    private var resampledLeft: UnsafeMutablePointer<Float>?
    private var resampledRight: UnsafeMutablePointer<Float>?
    private var resampledCapacity: Int = 0

    // MARK: - Stem Decomposition

    /// Whether stem decomposition is active (premium crossfade)
    var stemMode: Bool = false
    /// Decomposer that splits audio into bass/vocal/instrument stems
    var stemDecomposer: StemDecomposer?

    init(ringBuffer: CircularBuffer) {
        self.ringBuffer = ringBuffer
    }

    deinit {
        isValid = false
        interleavedBuffer?.deallocate()
        resampledLeft?.deallocate()
        resampledRight?.deallocate()
    }

    // MARK: - SRC Configuration

    /// Configure SRC based on the source track's actual sample rate.
    /// Called from tapPrepareCallback once the real format is known.
    func configureSRC(sourceSampleRate: Double) {
        let engineRate = 44100.0
        if abs(sourceSampleRate - engineRate) > 1.0 {
            needsSRC = true
            srcRatio = sourceSampleRate / engineRate
            srcPhase = 0.0
            prevSampleLeft = 0
            prevSampleRight = 0
        } else {
            needsSRC = false
            srcRatio = 1.0
        }
    }

    /// Resample planar audio from source rate to 44100Hz using linear interpolation,
    /// then write interleaved output to the ring buffer.
    func resampleAndWrite(left: UnsafePointer<Float>, right: UnsafePointer<Float>, inputFrameCount: Int) {
        // Calculate maximum output frames for this input block
        let maxOutputFrames = Int(Double(inputFrameCount) / srcRatio) + 2

        // Ensure resampled buffers are large enough
        if resampledCapacity < maxOutputFrames {
            resampledLeft?.deallocate()
            resampledRight?.deallocate()
            resampledLeft = UnsafeMutablePointer<Float>.allocate(capacity: maxOutputFrames)
            resampledRight = UnsafeMutablePointer<Float>.allocate(capacity: maxOutputFrames)
            resampledCapacity = maxOutputFrames
        }

        guard let outL = resampledLeft, let outR = resampledRight else { return }

        var outputCount = 0

        while srcPhase < Double(inputFrameCount) && outputCount < maxOutputFrames {
            let intIndex = Int(srcPhase)
            let frac = Float(srcPhase - Double(intIndex))

            // Get current and next sample (with boundary handling)
            let curL: Float
            let curR: Float
            let nextL: Float
            let nextR: Float

            if intIndex < 0 {
                // Should not happen, but safety
                curL = prevSampleLeft
                curR = prevSampleRight
                nextL = left[0]
                nextR = right[0]
            } else if intIndex == 0 && srcPhase < 1.0 {
                // First sample — interpolate from previous block's last sample
                curL = (intIndex == 0) ? left[0] : prevSampleLeft
                curR = (intIndex == 0) ? right[0] : prevSampleRight
                nextL = (intIndex + 1 < inputFrameCount) ? left[intIndex + 1] : curL
                nextR = (intIndex + 1 < inputFrameCount) ? right[intIndex + 1] : curR
            } else {
                curL = left[min(intIndex, inputFrameCount - 1)]
                curR = right[min(intIndex, inputFrameCount - 1)]
                nextL = (intIndex + 1 < inputFrameCount) ? left[intIndex + 1] : curL
                nextR = (intIndex + 1 < inputFrameCount) ? right[intIndex + 1] : curR
            }

            // Linear interpolation
            outL[outputCount] = curL + frac * (nextL - curL)
            outR[outputCount] = curR + frac * (nextR - curR)
            outputCount += 1

            srcPhase += srcRatio
        }

        // Save last samples for next block boundary
        if inputFrameCount > 0 {
            prevSampleLeft = left[inputFrameCount - 1]
            prevSampleRight = right[inputFrameCount - 1]
        }

        // Wrap phase to stay relative to next block
        srcPhase -= Double(inputFrameCount)

        // Write resampled output
        if outputCount > 0 {
            if stemMode, let decomposer = stemDecomposer {
                decomposer.decompose(left: outL, right: outR, frameCount: outputCount)
            } else {
                interleaveAndWrite(left: outL, right: outR, frameCount: outputCount)
            }
        }
    }

    /// Interleave planar audio and write to ring buffer (allocation-free in steady state)
    func interleaveAndWrite(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int) {
        let sampleCount = frameCount * 2

        // Resize buffer if needed (only happens on first call or frame count change)
        if bufferCapacity < sampleCount {
            interleavedBuffer?.deallocate()
            interleavedBuffer = UnsafeMutablePointer<Float>.allocate(capacity: sampleCount)
            bufferCapacity = sampleCount
        }

        guard let buffer = interleavedBuffer else { return }

        // Interleave using pointer arithmetic (no Swift array overhead)
        for i in 0..<frameCount {
            buffer[i * 2] = left[i]
            buffer[i * 2 + 1] = right[i]
        }

        ringBuffer.write(buffer, count: sampleCount)
    }
}

// MARK: - C-Style Tap Callbacks

private let tapInitCallback: MTAudioProcessingTapInitCallback = { tap, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

private let tapFinalizeCallback: MTAudioProcessingTapFinalizeCallback = { tap in
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<AudioTapContext>.fromOpaque(storage).release()
}

private let tapPrepareCallback: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<AudioTapContext>.fromOpaque(storage).takeUnretainedValue()

    context.sampleRate = processingFormat.pointee.mSampleRate
    context.channelCount = Int(processingFormat.pointee.mChannelsPerFrame)

    // Configure SRC if source rate differs from engine's fixed 44100Hz
    context.configureSRC(sourceSampleRate: context.sampleRate)
}

private let tapUnprepareCallback: MTAudioProcessingTapUnprepareCallback = { _ in
    // No-op
}

private let tapProcessCallback: MTAudioProcessingTapProcessCallback = {
    tap,
    numberFrames,
    flags,
    bufferListInOut,
    numberFramesOut,
    flagsOut
    in

    // 1. Pull audio from AVPlayer
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )

    guard status == noErr else { return }

    // 2. Access context
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<AudioTapContext>.fromOpaque(storage).takeUnretainedValue()
    guard context.isValid else { return }

    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    let frameCount = Int(numberFrames)

    // 3. Non-interleaved (planar)
    if bufferList.count >= 2,
       let leftData = bufferList[0].mData,
       let rightData = bufferList[1].mData {

        let left = leftData.assumingMemoryBound(to: Float.self)
        let right = rightData.assumingMemoryBound(to: Float.self)

        if context.needsSRC {
            // Resample to 44100Hz then write
            context.resampleAndWrite(left: left, right: right, inputFrameCount: frameCount)
        } else if context.stemMode, let decomposer = context.stemDecomposer {
            // Stem decomposition mode — split into bass/vocal/instrument
            decomposer.decompose(left: left, right: right, frameCount: frameCount)
        } else {
            // Standard path — interleave and write to ring buffer
            context.interleaveAndWrite(left: left, right: right, frameCount: frameCount)
        }

        // Silence AVPlayer output
        memset(leftData, 0, Int(bufferList[0].mDataByteSize))
        memset(rightData, 0, Int(bufferList[1].mDataByteSize))
    }
    // 4. Interleaved
    else if let audioBuffer = bufferList.first,
            let data = audioBuffer.mData {

        let floatBuffer = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size

        // For interleaved, we need to handle SRC and stem mode too
        if context.needsSRC || context.stemMode {
            // Deinterleave first
            let frameCount = sampleCount / 2
            let tempLeft = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
            let tempRight = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
            defer {
                tempLeft.deallocate()
                tempRight.deallocate()
            }
            for i in 0..<frameCount {
                tempLeft[i] = floatBuffer[i * 2]
                tempRight[i] = floatBuffer[i * 2 + 1]
            }
            if context.needsSRC {
                context.resampleAndWrite(left: tempLeft, right: tempRight, inputFrameCount: frameCount)
            } else if let decomposer = context.stemDecomposer {
                decomposer.decompose(left: tempLeft, right: tempRight, frameCount: frameCount)
            }
        } else {
            context.ringBuffer.write(floatBuffer, count: sampleCount)
        }

        // Silence AVPlayer output
        memset(data, 0, Int(audioBuffer.mDataByteSize))
    }
}

// MARK: - Audio Tap Processor

/// Manages MTAudioProcessingTap to bridge AVPlayer -> AudioEngine
@MainActor
final class AudioTapProcessor {

    private var tapContext: AudioTapContext?
    private var attachTask: Task<Void, Never>?
    private var currentAttachmentId: UUID?

    deinit {
        attachTask?.cancel()
    }

    // MARK: - Public API

    /// The current tap context (exposed for stem mode configuration)
    var context: AudioTapContext? { tapContext }

    func attachSync(to playerItem: AVPlayerItem, ringBuffer: CircularBuffer? = nil) {
        attachTask?.cancel()

        let context = AudioTapContext(
            ringBuffer: ringBuffer ?? AudioEngineService.shared.activeRingBuffer
        )
        tapContext = context

        let attachmentId = UUID()
        currentAttachmentId = attachmentId

        let asset = playerItem.asset
        let tracks = asset.tracks(withMediaType: .audio)

        if let audioTrack = tracks.first {
            // Sync path: track available, attach tap directly
            // SRC is handled inside the tap callback — no engine reconfiguration needed
            createAndAttachTap(
                to: playerItem,
                audioTrack: audioTrack,
                context: context
            )
        } else {
            // Async path: no tracks available yet
            attachTask = Task(priority: .userInitiated) {
                let asyncTracks = try? await asset.loadTracks(withMediaType: .audio)
                guard self.currentAttachmentId == attachmentId,
                      let track = asyncTracks?.first else { return }

                self.createAndAttachTap(
                    to: playerItem,
                    audioTrack: track,
                    context: context
                )
            }
        }
    }

    func detach() {
        attachTask?.cancel()
        attachTask = nil
        currentAttachmentId = nil

        // Clear the ring buffer this tap was writing to
        tapContext?.ringBuffer.clear()
        tapContext = nil
    }

    /// Release the tap context without clearing the ring buffer.
    /// Used during crossfade handoff where the ring buffer is still in use
    /// by the adopted player — clearing it would cause an audio dropout.
    func abandon() {
        attachTask?.cancel()
        attachTask = nil
        currentAttachmentId = nil
        tapContext = nil
    }

    // MARK: - Private

    private func createAndAttachTap(
        to playerItem: AVPlayerItem,
        audioTrack: AVAssetTrack,
        context: AudioTapContext
    ) {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: tapInitCallback,
            finalize: tapFinalizeCallback,
            prepare: tapPrepareCallback,
            unprepare: tapUnprepareCallback,
            process: tapProcessCallback
        )

        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapRef
        )

        guard status == noErr, let tap = tapRef else {
            Logger.error("Failed to create audio tap", category: .playback)
            return
        }

        let inputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParameters.audioTapProcessor = tap

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParameters]

        playerItem.audioMix = audioMix
    }
}
