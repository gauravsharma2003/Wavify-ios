//
//  CrossfadePlayerSlot.swift
//  Wavify
//
//  Lightweight AVPlayer wrapper for one crossfade slot.
//  Owns the player, item, tap, and observers. Does NOT manage AudioEngineService lifecycle.
//

import Foundation
import AVFoundation

@MainActor
final class CrossfadePlayerSlot {

    // MARK: - State

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private let audioTapProcessor = AudioTapProcessor()
    private var statusObserver: NSKeyValueObservation?
    private var timeObserver: Any?

    private(set) var isReady = false
    private(set) var song: Song?

    // MARK: - Callbacks

    var onReady: (() -> Void)?
    var onFailed: ((Error?) -> Void)?
    var onTimeUpdated: ((Double) -> Void)?

    // MARK: - Load

    /// Load a URL into this slot, writing audio to the specified ring buffer.
    func load(url: URL, expectedDuration: Double, song: Song, ringBuffer: CircularBuffer) {
        cleanup()
        self.song = song
        isReady = false

        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        // Don't autoplay — CrossfadeEngine controls when to start
        player?.pause()

        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    // Reconfigure the secondary source node for this track's format
                    let asset = item.asset
                    let tracks = asset.tracks(withMediaType: .audio)
                    if let audioTrack = tracks.first,
                       let formatDescriptions = audioTrack.formatDescriptions as? [CMFormatDescription],
                       let formatDesc = formatDescriptions.first,
                       let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                        let sampleRate = asbd.pointee.mSampleRate
                        let channels = Int(asbd.pointee.mChannelsPerFrame)
                        if sampleRate > 0 && channels > 0 {
                            AudioEngineService.shared.reconfigureSecondary(
                                sampleRate: sampleRate,
                                channels: channels
                            )
                        }
                    }

                    // Attach tap writing to the standby ring buffer
                    self.audioTapProcessor.attachSync(to: item, ringBuffer: ringBuffer)
                    self.isReady = true
                    self.onReady?()

                case .failed:
                    self.onFailed?(item.error)

                default:
                    break
                }
            }
        }

        setupTimeObserver()
    }

    // MARK: - Playback Control

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    // MARK: - Hand Off

    /// Transfer AVPlayer ownership to PlaybackService without stopping playback.
    /// Returns the player and item, then nils out local references (but keeps them playing).
    func handOffPlayer() -> (AVPlayer, AVPlayerItem)? {
        guard let p = player, let item = playerItem else { return nil }

        // Remove observers but don't pause or detach — playback continues
        if let obs = timeObserver {
            p.removeTimeObserver(obs)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil

        // Nil out local references without cleanup
        player = nil
        playerItem = nil
        song = nil
        isReady = false

        return (p, item)
    }

    // MARK: - Time Observer

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                let seconds = time.seconds.isNaN ? 0 : time.seconds
                self.onTimeUpdated?(seconds)
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil

        player?.pause()
        playerItem?.audioMix = nil
        audioTapProcessor.detach()

        player = nil
        playerItem = nil
        song = nil
        isReady = false
    }

    deinit {
        // Ensure observers are removed
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        statusObserver?.invalidate()
    }
}
