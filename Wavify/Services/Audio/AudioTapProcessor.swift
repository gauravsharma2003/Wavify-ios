//
//  AudioTapProcessor.swift
//  Wavify
//
//  MTAudioProcessingTap-based audio processor.
//  Acts as a bridge: Captures audio from AVPlayer (streaming) and writes it to the CircularBuffer.
//  Crucially, it SILENCES the pass-through audio so AVPlayer doesn't play raw sound.
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

    init(ringBuffer: CircularBuffer) {
        self.ringBuffer = ringBuffer
    }

    deinit {
        isValid = false
        interleavedBuffer?.deallocate()
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

    // NOTE:
    // We intentionally DO NOT reconfigure AudioEngine here.
    // Engine format must be pre-configured before attaching the tap
    // to avoid real-time thread stalls or silence.
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

        // Use allocation-free interleaving
        context.interleaveAndWrite(left: left, right: right, frameCount: frameCount)

        // Silence AVPlayer output
        memset(leftData, 0, Int(bufferList[0].mDataByteSize))
        memset(rightData, 0, Int(bufferList[1].mDataByteSize))
    }
    // 4. Interleaved
    else if let audioBuffer = bufferList.first,
            let data = audioBuffer.mData {

        let floatBuffer = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size

        context.ringBuffer.write(floatBuffer, count: sampleCount)

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

    func attachSync(to playerItem: AVPlayerItem) {
        attachTask?.cancel()

        let context = AudioTapContext(
            ringBuffer: AudioEngineService.shared.ringBuffer
        )
        tapContext = context

        let attachmentId = UUID()
        currentAttachmentId = attachmentId

        let asset = playerItem.asset
        let tracks = asset.tracks(withMediaType: .audio)

        if let audioTrack = tracks.first,
           let formatDescriptions = audioTrack.formatDescriptions as? [CMFormatDescription],
           let formatDesc = formatDescriptions.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            // Sync path: format available, reconfigure and attach
            let sampleRate = asbd.pointee.mSampleRate
            let channels = Int(asbd.pointee.mChannelsPerFrame)
            if sampleRate > 0 && channels > 0 {
                AudioEngineService.shared.reconfigure(
                    sampleRate: sampleRate,
                    channels: channels
                )
            }
            createAndAttachTap(
                to: playerItem,
                audioTrack: audioTrack,
                context: context
            )
        } else {
            // Async path: either no tracks or no format descriptions available
            attachTask = Task(priority: .userInitiated) {
                let asyncTracks = try? await asset.loadTracks(withMediaType: .audio)
                guard self.currentAttachmentId == attachmentId,
                      let track = asyncTracks?.first else { return }

                if let formatDescriptions = try? await track.load(.formatDescriptions),
                   let formatDesc = formatDescriptions.first,
                   let asbd =
                        CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {

                    let sampleRate = asbd.pointee.mSampleRate
                    let channels = Int(asbd.pointee.mChannelsPerFrame)

                    if sampleRate > 0 && channels > 0 {
                        AudioEngineService.shared.reconfigure(
                            sampleRate: sampleRate,
                            channels: channels
                        )
                    }
                }

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
        tapContext = nil

        AudioEngineService.shared.ringBuffer.clear()
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
