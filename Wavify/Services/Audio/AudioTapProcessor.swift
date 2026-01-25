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
    
    init(ringBuffer: CircularBuffer) {
        self.ringBuffer = ringBuffer
    }
    
    deinit {
        isValid = false
    }
}

// MARK: - C-Style Tap Callbacks

private let tapInitCallback: MTAudioProcessingTapInitCallback = { (tap, clientInfo, tapStorageOut) in
    tapStorageOut.pointee = clientInfo
}

private let tapFinalizeCallback: MTAudioProcessingTapFinalizeCallback = { (tap) in
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<AudioTapContext>.fromOpaque(storage).release()
}

private let tapPrepareCallback: MTAudioProcessingTapPrepareCallback = { (tap, maxFrames, processingFormat) in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<AudioTapContext>.fromOpaque(storage).takeUnretainedValue()
    
    let sampleRate = processingFormat.pointee.mSampleRate
    let channelCount = Int(processingFormat.pointee.mChannelsPerFrame)
    
    context.sampleRate = sampleRate
    context.channelCount = channelCount
    
    // CRITICAL: Notify AudioEngine of the format to prevent pitch shift/distortion
    Task { @MainActor in
        AudioEngineService.shared.reconfigure(sampleRate: sampleRate, channels: channelCount)
    }
}

private let tapUnprepareCallback: MTAudioProcessingTapUnprepareCallback = { (tap) in
    // No-op for now
}

private let tapProcessCallback: MTAudioProcessingTapProcessCallback = { (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
    // 1. Get source audio from AVPlayer
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )
    
    guard status == noErr else { return }
    
    // 2. Access Context
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<AudioTapContext>.fromOpaque(storage).takeUnretainedValue()
    guard context.isValid else { return }
    
    // 3. Process Buffers
    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    let frameCount = Int(numberFrames)
    
    // Check if we have multiple buffers (Non-Interleaved/Planar) or single buffer (Interleaved)
    if bufferList.count >= 2,
       let leftData = bufferList[0].mData,
       let rightData = bufferList[1].mData {
        
        // Handle Non-Interleaved (Planar) -> Need to Interleave for RingBuffer
        let left = leftData.assumingMemoryBound(to: Float.self)
        let right = rightData.assumingMemoryBound(to: Float.self)
        
        // Temporary buffer for interleaving
        // Note: allocating every frame is not ideal for realtime, but stack allocation is safe for small chunks
        // numberFrames is usually 4096 or 8192 max
        var interleaved = [Float](repeating: 0, count: frameCount * 2)
        
        for i in 0..<frameCount {
            interleaved[i * 2] = left[i]
            interleaved[i * 2 + 1] = right[i]
        }
        
        // Write interleaved data
        context.ringBuffer.write(interleaved, count: frameCount * 2)
        
        // Silence input
        memset(leftData, 0, Int(bufferList[0].mDataByteSize))
        memset(rightData, 0, Int(bufferList[1].mDataByteSize))
        
    } else if let audioBuffer = bufferList.first, let data = audioBuffer.mData {
        // Handle Interleaved (Standard) -> Just Copy
        let floatBuffer = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
        
        context.ringBuffer.write(floatBuffer, count: sampleCount)
        
        // Silence input
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
    
    // MARK: - Initialization
    
    init() {
        // No longer need to subscribe to legacy EQ settings
        // AudioEngineService handles new EQ
    }
    
    deinit {
        attachTask?.cancel()
    }

    // MARK: - Public API

    func attachSync(to playerItem: AVPlayerItem) {
        attachTask?.cancel()
        
        // Pass the shared ring buffer to the context
        let context = AudioTapContext(ringBuffer: AudioEngineService.shared.ringBuffer)
        tapContext = context
        
        let attachmentId = UUID()
        currentAttachmentId = attachmentId
        
        let asset = playerItem.asset
        let tracks = asset.tracks(withMediaType: .audio)
        
        if let audioTrack = tracks.first {
            createAndAttachTap(to: playerItem, audioTrack: audioTrack, context: context)
        } else {
            attachTask = Task(priority: .userInitiated) {
                let asyncTracks = try? await asset.loadTracks(withMediaType: .audio)
                guard self.currentAttachmentId == attachmentId, let asyncTracks = asyncTracks, let track = asyncTracks.first else { return }
                self.createAndAttachTap(to: playerItem, audioTrack: track, context: context)
            }
        }
    }
    
    func detach() {
        attachTask?.cancel()
        attachTask = nil
        currentAttachmentId = nil
        tapContext = nil
        // Clears the bridge
        AudioEngineService.shared.ringBuffer.clear()
    }
    
    func resetFilters() {
        // Handled by AudioEngineService now if needed
    }
    
    // MARK: - Private Methods
    
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
            Logger.error("Failed to create Tap", category: .playback)
            return
        }
        
        let inputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParameters.audioTapProcessor = tap
        
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParameters]
        
        playerItem.audioMix = audioMix
    }
}
