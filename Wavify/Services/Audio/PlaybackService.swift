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

    /// Expose the tap context so CrossfadeEngine can enable stem decomposition on the active track
    var activeTapContext: AudioTapContext? { audioTapProcessor.context }

    /// Which ring buffer the tap writes to (nil = default active buffer)
    var targetRingBuffer: CircularBuffer?

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    /// Whether audio is currently routed to an AirPlay device.
    /// When true, the audio tap is detached so AVPlayer outputs directly.
    private(set) var isAirPlayActive = false

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
    var onBufferingChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Move audio session setup to background to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async {
            self.setupAudioSession()
        }
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
    
    // MARK: - AirPlay Detection

    /// Check whether the current audio route includes an AirPlay output.
    static func currentRouteIsAirPlay() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { $0.portType == .airPlay }
    }

    /// Called on audio route change. Detaches the audio tap when AirPlay is active
    /// so AVPlayer outputs directly, and re-attaches it when back on local output.
    ///
    /// Does NOT touch the player's play/pause state — the player continues whatever
    /// it was doing. The caller (AudioPlayer) handles pausing if needed.
    func handleRouteChange() {
        let airPlay = Self.currentRouteIsAirPlay()
        guard airPlay != isAirPlayActive else { return }
        isAirPlayActive = airPlay

        if airPlay {
            // AirPlay ON: mute engine first (prevent double audio), then remove tap.
            // AVPlayer continues playing — its output goes directly to AirPlay.
            // ~20ms of silence as pre-zeroed buffered frames drain is imperceptible.
            Logger.log("AirPlay active — bypassing audio engine", category: .playback)
            AudioEngineService.shared.mute()
            playerItem?.audioMix = nil
            audioTapProcessor.detach()
            AudioEngineService.shared.stop()
        } else {
            // AirPlay OFF: re-attach tap and restart engine for local playback.
            // The player continues playing — tap captures audio immediately.
            Logger.log("AirPlay disconnected — restoring audio engine", category: .playback)
            guard let item = playerItem, item.status == .readyToPlay else { return }
            audioTapProcessor.attachSync(to: item, ringBuffer: targetRingBuffer)
            AudioEngineService.shared.flush()
            AudioEngineService.shared.start()
            // Unmute immediately — tap is already writing fresh audio to the ring buffer.
            // No delayed unmute needed since there's no stale data (just flushed).
            AudioEngineService.shared.unmute()
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
        player?.allowsExternalPlayback = false  // Audio-only: route via AirPlay audio, not video

        // Observe player status
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    self.onReady?(self.duration)
                    self.delegate?.playbackService(self, didBecomeReady: self.duration)

                    // Ensure session is active - move to background to avoid blocking
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? AVAudioSession.sharedInstance().setActive(true)
                    }

                    // Apply pending seek before playing
                    if let seekTime = self.pendingSeekTime, seekTime > 0 {
                        let cmTime = CMTime(seconds: seekTime, preferredTimescale: 1000)
                        await self.player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        self.currentTime = seekTime
                        self.pendingSeekTime = nil
                    }

                    // Check current AirPlay state
                    self.isAirPlayActive = Self.currentRouteIsAirPlay()

                    if self.isAirPlayActive {
                        // AirPlay active — skip tap/engine, let AVPlayer output directly
                        if autoPlay {
                            self.player?.play()
                            self.isPlaying = true
                            self.onPlayPauseChanged?(true)
                        }
                    } else {
                        // Local playback — attach tap and start engine
                        Task.detached(priority: .userInitiated) {
                            await AudioEngineService.shared.waitForInitialization()

                            await MainActor.run {
                                self.audioTapProcessor.attachSync(
                                    to: item,
                                    ringBuffer: self.targetRingBuffer
                                )
                                AudioEngineService.shared.flush()
                                AudioEngineService.shared.start()

                                if autoPlay {
                                    self.player?.play()
                                    self.isPlaying = true
                                    self.onPlayPauseChanged?(true)
                                }
                            }

                            try? await Task.sleep(nanoseconds: 100_000_000)

                            await MainActor.run {
                                AudioEngineService.shared.unmute()
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
        setupBufferObserver()
        setupTimeControlStatusObserver()
    }
    
    // MARK: - Buffer Observer
    
    private var bufferEmptyObserver: NSKeyValueObservation?
    private var bufferLikelyToKeepUpObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    
    private func setupBufferObserver() {
        bufferEmptyObserver = playerItem?.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                if item.isPlaybackBufferEmpty {
                    self.onBufferingChanged?(true)
                }
            }
        }
        
        bufferLikelyToKeepUpObserver = playerItem?.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                if item.isPlaybackLikelyToKeepUp {
                    self.onBufferingChanged?(false)
                }
            }
        }
    }
    
    private func setupTimeControlStatusObserver() {
        timeControlStatusObserver = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self = self else { return }
                // If the player actually starts playing, we are by definition not buffering (stalled).
                // This acts as a failsafe if isPlaybackLikelyToKeepUp is delayed or missed.
                if player.timeControlStatus == .playing {
                    self.onBufferingChanged?(false)
                }
            }
        }
    }
    
    private func handlePlayerFailure(error: Error?) {
        let errorDesc = error?.localizedDescription ?? "unknown"
        // Log detailed error info for debugging
        if let nsError = error as? NSError {
            Logger.warning("Player failed (attempt \(self.retryCount + 1)/\(self.maxRetries + 1)) - \(errorDesc) [code: \(nsError.code), domain: \(nsError.domain)]", category: .playback)
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                Logger.warning("  Underlying error: \(underlying.localizedDescription) [code: \(underlying.code), domain: \(underlying.domain)]", category: .playback)
            }
            if let url = currentLoadParameters?.url {
                Logger.warning("  URL host: \(url.host ?? "nil"), path prefix: \(String(url.path.prefix(30)))", category: .playback)
            }
        } else {
            Logger.warning("Player failed (attempt \(self.retryCount + 1)/\(self.maxRetries + 1)) - \(errorDesc)", category: .playback)
        }
        
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

        // Skip engine management during AirPlay (engine already stopped)
        if !isAirPlayActive {
            // 1. Mute output first to prevent glitchy sounds
            AudioEngineService.shared.mute()

            // 2. Stop engine (stops reading from buffer)
            AudioEngineService.shared.stop()
        }

        // 3. Pause player (stops decoding)
        player?.pause()

        // 4. Detach tap (stops writing to buffer)
        playerItem?.audioMix = nil
        audioTapProcessor.detach()

        if !isAirPlayActive {
            // 5. Flush buffer (clear stale samples)
            AudioEngineService.shared.flush()
        }

        player = nil
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
        player?.allowsExternalPlayback = false  // Audio-only: route via AirPlay audio, not video

        let autoPlay = params.autoPlay

        // Observe player status
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    Logger.log("Playback retry successful", category: .playback)

                    self.onReady?(self.duration)
                    self.delegate?.playbackService(self, didBecomeReady: self.duration)

                    if let seekTime = self.pendingSeekTime, seekTime > 0 {
                        let cmTime = CMTime(seconds: seekTime, preferredTimescale: 1000)
                        await self.player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        self.currentTime = seekTime
                        self.pendingSeekTime = nil
                    }

                    self.isAirPlayActive = Self.currentRouteIsAirPlay()

                    if self.isAirPlayActive {
                        if autoPlay {
                            self.player?.play()
                            self.isPlaying = true
                            self.onPlayPauseChanged?(true)
                        }
                    } else {
                        Task.detached(priority: .userInitiated) {
                            await AudioEngineService.shared.waitForInitialization()

                            await MainActor.run {
                                self.audioTapProcessor.attachSync(
                                    to: item,
                                    ringBuffer: self.targetRingBuffer
                                )
                                AudioEngineService.shared.flush()
                                AudioEngineService.shared.start()

                                if autoPlay {
                                    self.player?.play()
                                    self.isPlaying = true
                                    self.onPlayPauseChanged?(true)
                                }
                            }

                            try? await Task.sleep(nanoseconds: 100_000_000)

                            await MainActor.run {
                                AudioEngineService.shared.unmute()
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
        setupTimeControlStatusObserver()
    }
    
    func play() {
        if isAirPlayActive {
            // AirPlay — AVPlayer outputs directly, no engine needed
            player?.play()
        } else {
            AudioEngineService.shared.flush()
            AudioEngineService.shared.start()
            player?.play()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                AudioEngineService.shared.unmute()
            }
        }
        isPlaying = true
        onPlayPauseChanged?(true)
    }

    func pause() {
        player?.pause()
        if !isAirPlayActive {
            AudioEngineService.shared.mute()
            AudioEngineService.shared.stop()
        }
        isPlaying = false
        onPlayPauseChanged?(false)
        onBufferingChanged?(false)
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: Double) {
        if !isAirPlayActive {
            AudioEngineService.shared.mute()
        }

        currentTime = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)

        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isAirPlayActive else { return }
                AudioEngineService.shared.flush()
                try? await Task.sleep(nanoseconds: 80_000_000)
                AudioEngineService.shared.unmute()
            }
        }
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
                Task.detached(priority: .userInitiated) {
                    if let image = await ImageCache.shared.image(for: url) {
                        await MainActor.run {
                            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                            self.cachedArtwork = artwork
                            self.cachedSongId = song.id
                            // Merge artwork with current info to avoid overwriting playback state
                            if var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                                currentInfo[MPMediaItemPropertyArtwork] = artwork
                                MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                            }
                        }
                    } else {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            if let image = UIImage(data: data) {
                                await ImageCache.shared.store(image, for: url)
                                await MainActor.run {
                                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                                    self.cachedArtwork = artwork
                                    self.cachedSongId = song.id
                                    // Merge artwork with current info to avoid overwriting playback state
                                    if var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                                        currentInfo[MPMediaItemPropertyArtwork] = artwork
                                        MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                                    }
                                }
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

    /// - Parameter manageEngine: When false, skips AudioEngineService mute/stop/flush
    ///   (used during crossfade handoff where the engine must keep running).
    func cleanup(manageEngine: Bool = true) {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil

        bufferEmptyObserver?.invalidate()
        bufferEmptyObserver = nil

        bufferLikelyToKeepUpObserver?.invalidate()
        bufferLikelyToKeepUpObserver = nil

        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil

        // Skip engine management during AirPlay (engine already stopped/muted)
        // to avoid leaving the engine in a stale mute state across song transitions
        let shouldManageEngine = manageEngine && !isAirPlayActive

        if shouldManageEngine {
            // 1. Mute output first to prevent any glitchy sounds during cleanup
            AudioEngineService.shared.mute()

            // 2. Stop engine (stops reading from buffer)
            AudioEngineService.shared.stop()
        }

        // 3. Pause player (stops decoding)
        player?.pause()

        // 4. Remove audio mix and detach tap (stops writing to buffer)
        playerItem?.audioMix = nil
        audioTapProcessor.detach()

        if shouldManageEngine {
            // 5. Flush buffer (clear any remaining stale samples)
            AudioEngineService.shared.flush()
        }

        player = nil
        playerItem = nil
        currentTime = 0

        cachedArtwork = nil
        cachedSongId = nil
    }

    // MARK: - Crossfade Adoption

    /// Take ownership of an already-playing AVPlayer from a crossfade slot.
    /// Sets up time/buffer/status observers without touching AudioEngineService.
    /// The crossfade slot's tap is already attached to the playerItem and writing
    /// to the correct (now-active) ring buffer — do NOT re-attach.
    func adoptPlayer(_ adoptedPlayer: AVPlayer, playerItem adoptedItem: AVPlayerItem, duration expectedDuration: Double) {
        // Clean up current player without stopping engine
        cleanup(manageEngine: false)

        player = adoptedPlayer
        playerItem = adoptedItem
        duration = expectedDuration
        isPlaying = true
        hasFiredSongEnd = false

        // Sync currentTime from the adopted player's actual position
        // (it's been playing during crossfade, so it's not at 0)
        let playerSeconds = adoptedPlayer.currentTime().seconds
        currentTime = playerSeconds.isNaN ? 0 : playerSeconds

        // NOTE: Do NOT call audioTapProcessor.attachSync here.
        // The crossfade slot's tap is already attached to this playerItem
        // and writing to the correct ring buffer. Re-attaching would replace
        // the audioMix with a new tap targeting the wrong buffer.

        setupTimeObserver()
        setupBufferObserver()
        setupTimeControlStatusObserver()

        onPlayPauseChanged?(true)
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}
