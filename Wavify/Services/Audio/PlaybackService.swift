//
//  PlaybackService.swift
//  Wavify
//
//  Core playback infrastructure: AVPlayer with MTAudioProcessingTap EQ support
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
                    // Attach EQ tap BEFORE playing to prevent audio muting
                    self.audioTapProcessor.attachSync(to: item)

                    self.onReady?(self.duration)
                    self.delegate?.playbackService(self, didBecomeReady: self.duration)

                    // Apply pending seek before playing
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
                    let error = item.error
                    let errorDesc = error?.localizedDescription ?? "unknown"
                    let nsError = error as NSError?
                    let errorCode = nsError?.code ?? 0
                    let errorDomain = nsError?.domain ?? "unknown"
                    Logger.warning("Player failed (attempt \(self.retryCount + 1)/\(self.maxRetries + 1)) - \(errorDomain):\(errorCode) \(errorDesc)", category: .playback)
                    
                    // Attempt retry if we haven't exceeded max retries
                    if self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        let delay = pow(2.0, Double(self.retryCount - 1)) * 0.5 // 0.5s, 1s, 2s
                        
                        Logger.log("Retrying playback in \(delay)s...", category: .playback)
                        
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        
                        // Try to get fresh URL first (handles expired URL case)
                        if let onRetryNeeded = self.onRetryNeeded {
                            onRetryNeeded { [weak self] freshUrl in
                                guard let self = self else { return }
                                Task { @MainActor in
                                    if let freshUrl = freshUrl,
                                       let params = self.currentLoadParameters {
                                        // Update stored parameters with fresh URL
                                        self.currentLoadParameters = (freshUrl, params.expectedDuration, params.autoPlay, params.seekTo, params.headers)
                                        self.retryLoad(url: freshUrl)
                                    } else if let params = self.currentLoadParameters {
                                        // Fall back to original URL
                                        self.retryLoad(url: params.url)
                                    }
                                }
                            }
                        } else if let params = self.currentLoadParameters {
                            // No fresh URL callback, retry with original URL
                            self.retryLoad(url: params.url)
                        }
                    } else {
                        // Max retries exceeded, report failure
                        Logger.error("Player failed after \(self.maxRetries) retries", category: .playback, error: error)
                        self.onFailed?(error)
                        self.delegate?.playbackService(self, didFail: error)
                    }
                    
                default:
                    break
                }
            }
        }
        
        setupTimeObserver()
    }
    
    /// Internal retry helper - loads with fresh URL while preserving retry count
    private func retryLoad(url: URL) {
        guard let params = currentLoadParameters else { return }
        
        // Clean up existing player but don't reset retry count
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
        
        // Attach EQ will happen in readyToPlay
        
        let autoPlay = params.autoPlay
        
        // Observe player status
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    Logger.log("Playback retry successful", category: .playback)

                    // CRITICAL: Attach EQ tap BEFORE playing to prevent audio muting
                    self.audioTapProcessor.attachSync(to: item)

                    self.onReady?(self.duration)
                    self.delegate?.playbackService(self, didBecomeReady: self.duration)

                    // Apply pending seek before playing
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
                    let error = item.error
                    let errorDesc = error?.localizedDescription ?? "unknown"
                    let nsError = error as NSError?
                    let errorCode = nsError?.code ?? 0
                    let errorDomain = nsError?.domain ?? "unknown"
                    Logger.warning("Retry failed (attempt \(self.retryCount + 1)/\(self.maxRetries + 1)) - \(errorDomain):\(errorCode) \(errorDesc)", category: .playback)
                    
                    if self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        let delay = pow(2.0, Double(self.retryCount - 1)) * 0.5
                        
                        Logger.log("Retrying playback in \(delay)s...", category: .playback)
                        
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        
                        if let onRetryNeeded = self.onRetryNeeded {
                            onRetryNeeded { [weak self] freshUrl in
                                guard let self = self else { return }
                                Task { @MainActor in
                                    if let freshUrl = freshUrl,
                                       let params = self.currentLoadParameters {
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
                    } else {
                        Logger.error("Player failed after \(self.maxRetries) retries. Error: \(error?.localizedDescription ?? "unknown")", category: .playback, error: error)
                        self.onFailed?(error)
                        self.delegate?.playbackService(self, didFail: error)
                    }
                    
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
        
        // Reset EQ filter states to prevent artifacts after seek
        audioTapProcessor.resetFilters()
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
        
        // Use cached artwork if same song, otherwise load new artwork
        if let cachedArtwork = cachedArtwork, cachedSongId == song.id {
            // Same song - reuse cached artwork (prevents flicker during seek)
            nowPlayingInfo[MPMediaItemPropertyArtwork] = cachedArtwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        } else {
            // New song - load high-resolution artwork (544px) for lock screen display
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
                        // Fallback to direct fetch and cache
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
            
            // Set info immediately without artwork for new songs
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
        
        // CRITICAL: Clear audioMix BEFORE detaching tap to stop audio engine callbacks
        playerItem?.audioMix = nil
        
        player?.pause()
        player = nil
        
        // Now safe to detach EQ tap since audio engine is no longer using it
        audioTapProcessor.detach()
        
        playerItem = nil
        currentTime = 0
        
        // Clear artwork cache
        cachedArtwork = nil
        cachedSongId = nil
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}
