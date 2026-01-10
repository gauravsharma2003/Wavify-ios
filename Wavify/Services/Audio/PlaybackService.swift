//
//  PlaybackService.swift
//  Wavify
//
//  Core playback infrastructure: AVPlayer, audio session, remote commands, time observer
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine

/// Delegate protocol for playback events
@MainActor
protocol PlaybackServiceDelegate: AnyObject {
    func playbackService(_ service: PlaybackService, didUpdateTime currentTime: Double)
    func playbackService(_ service: PlaybackService, didReachEndOfSong: Void)
    func playbackService(_ service: PlaybackService, didBecomeReady duration: Double)
    func playbackService(_ service: PlaybackService, didFail error: Error?)
}

/// Core playback service handling AVPlayer and media controls
@MainActor
class PlaybackService {
    // MARK: - Properties
    
    weak var delegate: PlaybackServiceDelegate?
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    
    // Callbacks for coordinator
    var onPlayPauseChanged: ((Bool) -> Void)?
    var onTimeUpdated: ((Double) -> Void)?
    var onSongEnded: (() -> Void)?
    var onReady: ((Double) -> Void)?
    var onFailed: ((Error?) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        setupAudioSession()
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
        } catch {
            Logger.error("Failed to setup audio session", category: .playback, error: error)
        }
    }
    
    // MARK: - Playback Control
    
    /// Load and prepare a URL for playback
    func load(url: URL, expectedDuration: Double) {
        cleanup()
        
        // Set duration from API before player reports
        duration = expectedDuration
        
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Observe player status
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    self.onReady?(self.duration)
                    self.delegate?.playbackService(self, didBecomeReady: self.duration)
                    self.player?.play()
                    self.isPlaying = true
                    self.onPlayPauseChanged?(true)
                    
                case .failed:
                    let error = item.error
                    Logger.error("Player failed", category: .playback, error: error)
                    self.onFailed?(error)
                    self.delegate?.playbackService(self, didFail: error)
                    
                default:
                    break
                }
            }
        }
        
        setupTimeObserver()
    }
    
    func play() {
        player?.play()
        isPlaying = true
        onPlayPauseChanged?(true)
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        onPlayPauseChanged?(false)
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }
    
    func seekToStart() {
        seek(to: 0)
    }
    
    // MARK: - Time Observer
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                let seconds = time.seconds.isNaN ? 0 : time.seconds
                self.currentTime = min(seconds, self.duration)
                
                self.onTimeUpdated?(self.currentTime)
                self.delegate?.playbackService(self, didUpdateTime: self.currentTime)
                
                // Check if song should end
                if self.duration > 0 && seconds >= self.duration - 0.5 {
                    self.onSongEnded?()
                    self.delegate?.playbackService(self, didReachEndOfSong: ())
                }
            }
        }
    }
    
    // MARK: - Now Playing Info
    
    func updateNowPlayingInfo(song: Song, isPlaying: Bool, currentTime: Double, duration: Double) {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration
        ]
        
        // Load artwork asynchronously using ImageCache
        if let url = URL(string: song.thumbnailUrl) {
            Task {
                if let image = await ImageCache.shared.image(for: url) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                } else {
                    // Fallback to direct fetch and cache
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            await ImageCache.shared.store(image, for: url)
                            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                        }
                    } catch {
                        Logger.error("Failed to load artwork", category: .playback, error: error)
                    }
                }
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
        player = nil
        playerItem = nil
        currentTime = 0
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}
