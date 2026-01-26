//
//  CircularBuffer.swift
//  Wavify
//
//  A high-performance, thread-safe circular buffer for bridging AudioTap to AVAudioEngine.
//  Uses atomic variables to ensure lock-free access on the real-time audio thread.
//

import Foundation
import Accelerate
import os.lock

/// A thread-safe, lock-free ring buffer for float audio data.
/// Critical for transferring data from MTAudioProcessingTap (realtime) to AVAudioSourceNode (realtime).
final class CircularBuffer {
    
    // MARK: - Properties
    
    /// The raw buffer storage
    private var buffer: UnsafeMutablePointer<Float>
    
    /// Capacity in float samples
    private let capacity: Int
    
    /// Read index (atomic-like behavior via memory barriers)
    private var readIndex: Int = 0
    
    /// Write index (atomic-like behavior via memory barriers)
    private var writeIndex: Int = 0
    
    /// Lock for non-critical operations (reset/cleanup) - NOT used in read/write
    private let stateLock = os_unfair_lock_t.allocate(capacity: 1)
    
    // MARK: - Initialization
    
    /// Initialize with capacity in samples (e.g., 44100 * 2 = 1 second stereo)
    init(capacity: Int) {
        self.capacity = capacity
        // Allocate aligned memory for optimized access
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.buffer.initialize(repeating: 0, count: capacity)
        
        stateLock.initialize(to: os_unfair_lock_s())
    }
    
    deinit {
        buffer.deallocate()
        stateLock.deallocate()
    }
    
    // MARK: - Real-time Methods
    
    /// Track overflow/underrun for diagnostics
    private var overflowCount: Int = 0
    private var underrunCount: Int = 0
    private var lastLogTime: UInt64 = 0

    /// Write data into the buffer. RETURNS TRUE if all data was written.
    /// Thread-safe for single-producer context (AudioTap).
    @discardableResult
    func write(_ data: UnsafePointer<Float>, count: Int) -> Bool {
        let availableSpace = capacity - (writeIndex - readIndex)

        if availableSpace < count {
            // Buffer overflow - drop data or handle gracefully
            // In realtime audio, dropping is better than blocking
            overflowCount += 1
            logDiagnosticsIfNeeded()
            return false
        }
        
        let writePtr = writeIndex % capacity
        let spaceToEnd = capacity - writePtr
        
        if count <= spaceToEnd {
            // One continuous write
            buffer.advanced(by: writePtr).assign(from: data, count: count)
        } else {
            // Wrap around
            buffer.advanced(by: writePtr).assign(from: data, count: spaceToEnd)
            buffer.assign(from: data.advanced(by: spaceToEnd), count: count - spaceToEnd)
        }
        
        // Memory barrier to ensure data is visible before index update
        OSMemoryBarrier()
        
        writeIndex += count
        return true
    }
    
    /// Read data from the buffer. RETURNS actual frames read.
    /// Thread-safe for single-consumer context (AVAudioSourceNode).
    func read(into outBuffer: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let availableData = writeIndex - readIndex

        if availableData <= 0 {
            // Buffer underrun - output silence
            underrunCount += 1
            logDiagnosticsIfNeeded()
            memset(outBuffer, 0, count * MemoryLayout<Float>.size)
            return 0
        }
        
        let toRead = min(availableData, count)
        let readPtr = readIndex % capacity
        let spaceToEnd = capacity - readPtr
        
        if toRead <= spaceToEnd {
            // One continuous read
            outBuffer.assign(from: buffer.advanced(by: readPtr), count: toRead)
        } else {
            // Wrap around
            outBuffer.assign(from: buffer.advanced(by: readPtr), count: spaceToEnd)
            outBuffer.advanced(by: spaceToEnd).assign(from: buffer, count: toRead - spaceToEnd)
        }
        
        // Zero pad if we don't have enough data
        if toRead < count {
            memset(outBuffer.advanced(by: toRead), 0, (count - toRead) * MemoryLayout<Float>.size)
        }
        
        // Memory barrier
        OSMemoryBarrier()
        
        readIndex += toRead
        return toRead
    }
    
    /// Log diagnostics periodically (max once per second) to avoid spam
    private func logDiagnosticsIfNeeded() {
        let now = mach_absolute_time()
        // Only log once per second (approximate)
        if now - lastLogTime > 1_000_000_000 {
            lastLogTime = now
            if overflowCount > 0 || underrunCount > 0 {
                print("[CircularBuffer] Overflow: \(overflowCount), Underrun: \(underrunCount), Fill: \(availableFrames)/\(capacity)")
            }
        }
    }

    /// Clear buffer contents safely
    func clear() {
        os_unfair_lock_lock(stateLock)
        readIndex = 0
        // Reset diagnostics for new song
        overflowCount = 0
        underrunCount = 0
        writeIndex = 0
        buffer.initialize(repeating: 0, count: capacity)
        os_unfair_lock_unlock(stateLock)
    }
    
    /// Current fill level
    var availableFrames: Int {
        return writeIndex - readIndex
    }
}
