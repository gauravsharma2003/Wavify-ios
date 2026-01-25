//
//  PlaybackService.swift
//  Wavify
//
//  Core playback infrastructure: AVPlayer with MTAudioProcessingTap bridging to AudioEngineService
//
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

/// Core playback service handling AVPlayer with real-time EQ via MTAudioProcessingTap
@MainActor
class PlaybackService {
    // MARK: - Properties
    
    weak var delegate: PlaybackServiceDelegate?
    
    // AVPlayer for streaming
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    
    // Audio processing tap for EQ
    private let audioTapProcessor = AudioTapProcessor()
    
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    
    // Cached artwork to prevent reloading during seek
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedSongId: String?
    
    // Retry mechanism
    private var retryCount = 0
    private let maxRetries = 3
    private var currentLoadParameters: (url: URL, expectedDuration: Double, autoPlay: Bool, seekTo: Double?, headers: [String: String]?)?
    
    /// Callback to request fresh URL for retry (called when URL might have expired)
    var onRetryNeeded: ((_ completion: @escaping (URL?) -> Void) -> Void)?
    
    /// Whether audio is currently loaded and ready for playback
    var isAudioLoaded: Bool {
        player != nil && playerItem?.status == .readyToPlay
    }
    
    /// Pending seek position to apply when player is ready (for session resume)
    private var pendingSeekTime: Double?
    
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
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            Logger.error("Failed to setup audio session", category: .playback, error: error)
        }
    }
    
    // MARK: - Playback Control
    
    /// Load and prepare a URL for playback
    /// - Parameters:
    ///   - url: The URL to load
    ///   - expectedDuration: The expected duration in seconds
    ///   - autoPlay: Whether to start playing automatically when ready (default: true)
    ///   - seekTo: Optional position to seek to when ready before playing
    func load(url: URL, expectedDuration: Double, autoPlay: Bool = true, seekTo: Double? = nil, headers: [String: String]? = nil) {
        // Ensure audio session is active before loading
        setupAudioSession()

        cleanup()

        // Reset retry count for new load
        retryCount = 0
        currentLoadParameters = (url, expectedDuration, autoPlay, seekTo, headers)

        // Set duration from API before player reports
        duration = expectedDuration
        pendingSeekTime = seekTo

        if let headers = headers {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            let asset = AVURLAsset(url: url, options: options)
            playerItem = AVPlayerItem(asset: asset)
        } else {
            playerItem = AVPlayerItem(url: url)
        }
        player = AVPlayer(playerItem: playerItem)
        
        // Observe player status
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    self.onReady?(self.duration)
                    self.delegate?.playbackService(self, didBecomeReady: self.duration)
                    
                    // Ensure session is active
                    try? AVAudioSession.sharedInstance().setActive(true)
                    
                    // Apply pending seek before playing
                    if let seekTime = self.pendingSeekTime, seekTime > 0 {
                        let cmTime = CMTime(seconds: seekTime, preferredTimescale: 1000)
                        await self.player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        self.currentTime = seekTime
                        self.pendingSeekTime = nil
                    }
                    
                    // Start the Audio Engine via AudioEngineService
                    AudioEngineService.shared.start()
                    
                    if autoPlay {
                        self.player?.play()
                        self.isPlaying = true
                        self.onPlayPauseChanged?(true)
                    }
                    
                    // Attach EQ tap AFTER playback starts
                    self.audioTapProcessor.attachSync(to: item)
                    
                    // Workaround for startup silence/synchronization
                    if autoPlay {
                        Task {
                            // Short pause/play sequence to sync graph
                             try? await Task.sleep(nanoseconds: 200_000_000)
                             if self.isPlaying {
                                 // Just ensure we are playing
                                 self.player?.play()
                             }
                        }
                    }
                    
                case .failed:
                    self.handlePlayerFailure(error: item.error)
                    
                default:
                    break
                }
            }
        }
        
        setupTimeObserver()
    }
    
    private func handlePlayerFailure(error: Error?) {
        let errorDesc = error?.localizedDescription ?? "unknown"
        Logger.warning("Player failed (attempt \(self.retryCount + 1)/\(self.maxRetries + 1)) - \(errorDesc)", category: .playback)
        
        if self.retryCount < self.maxRetries {
            self.retryCount += 1
            let delay = pow(2.0, Double(self.retryCount - 1)) * 0.5
            
            Logger.log("Retrying playback in \(delay)s...", category: .playback)
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                if let onRetryNeeded = self.onRetryNeeded {
                    onRetryNeeded { [weak self] freshUrl in
                        guard let self = self else { return }
                        Task { @MainActor in
                            if let freshUrl = freshUrl, let params = self.currentLoadParameters {
                                self.currentLoadParameters = (freshUrl, params.expectedDuration, params.autoPlay, params.seekTo, params.headers)
                                self.retryLoad(url: freshUrl)
                            } else if let params = self.currentLoadParameters {
                                self.retryLoad(url: params.url)
                            }
                        }
                    }
                } else if let params = self.currentLoadParameters {
                    self.retryLoad(url: params.url)
                }
            }
        } else {
            Logger.error("Player failed after \(self.maxRetries) retries", category: .playback, error: error)
            self.onFailed?(error)
            self.delegate?.playbackService(self, didFail: error)
        }
    }
    
    /// Internal retry helper - loads with fresh URL while preserving retry count
    private func retryLoad(url: URL) {
        guard let params = currentLoadParameters else { return }
        
        // Cleanup existing player
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
        player = nil
        audioTapProcessor.detach()
        playerItem = nil
        
        // Critical: Flush Audio Engine buffer
        AudioEngineService.shared.flush()
        
        // Set duration and pending seek from stored parameters
        duration = params.expectedDuration
        pendingSeekTime = params.seekTo
        
        if let headers = params.headers {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            let asset = AVURLAsset(url: url, options: options)
            playerItem = AVPlayerItem(asset: asset)
        } else {
            playerItem = AVPlayerItem(url: url)
        }
        player = AVPlayer(playerItem: playerItem)
        
        let autoPlay = params.autoPlay
        
        // Observe player status
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    Logger.log("Playback retry successful", category: .playback)
                    
                    // Start Engine
                    AudioEngineService.shared.start()

                    self.audioTapProcessor.attachSync(to: item)

                    self.onReady?(self.duration)
                    self.delegate?.playbackService(self, didBecomeReady: self.duration)

                    if let seekTime = self.pendingSeekTime, seekTime > 0 {
                        let cmTime = CMTime(seconds: seekTime, preferredTimescale: 1000)
                        await self.player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        self.currentTime = seekTime
                        self.pendingSeekTime = nil
                    }

                    if autoPlay {
                        self.player?.play()
                        self.isPlaying = true
                        self.onPlayPauseChanged?(true)
                    }
                    
                case .failed:
                    self.handlePlayerFailure(error: item.error)
                    
                default:
                    break
                }
            }
        }
        
        setupTimeObserver()
    }
    
    func play() {
        AudioEngineService.shared.start()
        player?.play()
        isPlaying = true
        onPlayPauseChanged?(true)
    }
    
    func pause() {
        player?.pause()
        // We keep audio engine running briefly or stop it?
        // Stopping it immediately might be fine, but starting it takes time.
        // Let's stop it for battery's sake, but maybe we can keep it for short pauses?
        // For robustness, let's keep it simple: stop implies stop.
        // Actually, if we stop AudioEngine, we might lose tail sounds (reverb/echo).
        // A better approach is to pause AVPlayer but keep Engine running if user might resume soon.
        // But for minimizing bugs:
        AudioEngineService.shared.stop()
        
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
        
        // Reset EQ filter states
        audioTapProcessor.resetFilters()
        // Also flush engine buffer? Maybe not necessary as it's a seek.
        // But we might have old samples in ring buffer.
        AudioEngineService.shared.flush()
    }
    
    func seekToStart() {
        seek(to: 0)
    }
    
    // MARK: - Time Observer

    /// Flag to prevent duplicate song end callbacks
    private var hasFiredSongEnd = false

    private func setupTimeObserver() {
        // Reset the flag for new song
        hasFiredSongEnd = false

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let seconds = time.seconds.isNaN ? 0 : time.seconds
                self.currentTime = min(seconds, self.duration)

                self.onTimeUpdated?(self.currentTime)
                self.delegate?.playbackService(self, didUpdateTime: self.currentTime)

                // Fallback song end detection if AVPlayerItemDidPlayToEndTime doesn't fire
                if self.duration > 0 && seconds >= self.duration - 0.5 && !self.hasFiredSongEnd {
                    self.hasFiredSongEnd = true
                    // Wait slightly before calling song ended to letting buffers drain
                    // (Optional, but safe)
                    self.onSongEnded?()
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
        
        if let cachedArtwork = cachedArtwork, cachedSongId == song.id {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = cachedArtwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        } else {
            let highResUrl = ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
            if let url = URL(string: highResUrl) {
                Task {
                    if let image = await ImageCache.shared.image(for: url) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        self.cachedArtwork = artwork
                        self.cachedSongId = song.id
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                    } else {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            if let image = UIImage(data: data) {
                                await ImageCache.shared.store(image, for: url)
                                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                                self.cachedArtwork = artwork
                                self.cachedSongId = song.id
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
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        
        playerItem?.audioMix = nil
        
        player?.pause()
        player = nil
        
        audioTapProcessor.detach()
        AudioEngineService.shared.flush()
        AudioEngineService.shared.stop()
        
        playerItem = nil
        currentTime = 0
        
        cachedArtwork = nil
        cachedSongId = nil
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}
