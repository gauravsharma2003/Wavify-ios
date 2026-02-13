//
//  SharePlayManager.swift
//  Wavify
//
//  WebSocket-based manager for synchronized listening via Metrolist relay.
//  Replaces the old GroupActivities/SharePlay implementation.
//

import Foundation
import Observation
import UIKit

// MARK: - Types

enum SharePlayRole: String {
    case none
    case host
    case guest
}

enum SharePlayConnectionStatus: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case reconnecting = "Reconnecting..."
    case waitingApproval = "Waiting for approval..."
    case error = "Error"
}

// MARK: - SharePlayManager (WebSocket-based)

@MainActor
@Observable
final class SharePlayManager {
    static let shared = SharePlayManager()

    // MARK: - Observable State

    private(set) var isSessionActive = false
    private(set) var role: SharePlayRole = .none
    private(set) var participantCount: Int = 0
    private(set) var connectionStatus: SharePlayConnectionStatus = .disconnected
    private(set) var pendingSuggestions: [SongSuggestion] = []

    /// Set to true when applying remote state to prevent echo broadcasts
    private(set) var isApplyingRemoteState = false

    var isHost: Bool { role == .host }
    var isGuest: Bool { role == .guest }

    // Room state
    private(set) var roomCode: String?
    var username: String {
        get { ListenTogetherClient.persistedUsername }
        set { ListenTogetherClient.persistedUsername = newValue }
    }
    private(set) var connectedUsers: [RoomUser] = []
    private(set) var pendingJoinRequests: [JoinRequest] = []
    var serverUrl: String = "wss://metroserver.meowery.eu/ws"

    private(set) var userId: String?
    private(set) var sessionToken: String?
    private(set) var errorMessage: String?

    // MARK: - Private

    private let client = ListenTogetherClient()
    private var syncTimer: Timer?
    private var pendingSyncPlayback: SyncPlaybackPayload?

    // MARK: - Init

    private init() {
        setupClientCallbacks()
    }

    // MARK: - Client Callbacks

    private func setupClientCallbacks() {
        Task {
            await client.setCallbacks(
                onMessage: { [weak self] type, data in
                    Task { @MainActor in
                        self?.handleMessage(type: type, payload: data)
                    }
                },
                onStateChange: { [weak self] state in
                    Task { @MainActor in
                        self?.handleConnectionStateChange(state)
                    }
                }
            )
        }
    }

    private func handleConnectionStateChange(_ state: ListenTogetherClient.ConnectionState) {
        switch state {
        case .disconnected:
            connectionStatus = .disconnected
        case .connecting:
            connectionStatus = .connecting
        case .connected:
            connectionStatus = .connected
        case .reconnecting:
            connectionStatus = .reconnecting
        }
    }

    // MARK: - Room Management

    func createRoom(username: String) {
        self.username = username
        guard let url = URL(string: serverUrl) else { return }

        connectionStatus = .connecting
        Task {
            await client.connect(to: url)
            let payload = CreateRoomPayload(username: username)
            try? await client.send(type: "create_room", payload: payload)
        }
    }

    func joinRoom(code: String, username: String) {
        self.username = username
        guard let url = URL(string: serverUrl) else { return }

        connectionStatus = .connecting
        Task {
            await client.connect(to: url)
            let payload = JoinRoomPayload(roomCode: code, username: username)
            try? await client.send(type: "join_room", payload: payload)
            connectionStatus = .waitingApproval
        }
    }

    func approveJoin(userId: String) {
        let payload = ApproveJoinPayload(userId: userId)
        pendingJoinRequests.removeAll { $0.userId == userId }
        Task {
            try? await client.send(type: "approve_join", payload: payload)
        }
    }

    func rejectJoin(userId: String) {
        let payload = RejectJoinPayload(userId: userId)
        pendingJoinRequests.removeAll { $0.userId == userId }
        Task {
            try? await client.send(type: "reject_join", payload: payload)
        }
    }

    func endSession() {
        Task {
            // leave_room has no payload
            try? await client.send(type: "leave_room")
            await client.disconnect()
        }
        cleanup()
        Logger.log("Listen Together session ended by user", category: .sharePlay)
    }

    // MARK: - Host Broadcasting

    func broadcastPlaybackState(isPlaying: Bool, currentTime: Double) {
        guard isHost, isSessionActive, !isApplyingRemoteState else { return }
        let action: PlaybackAction = isPlaying ? .play : .pause
        let positionMs = Int(currentTime * 1000)
        let serverTime = Int64(Date().timeIntervalSince1970 * 1000)
        let payload = PlaybackActionPayload(
            action: action,
            position: positionMs,
            serverTime: serverTime
        )
        Task {
            try? await client.send(type: "playback_action", payload: payload)
        }
    }

    func broadcastTrackChange(song: Song) {
        guard isHost, isSessionActive, !isApplyingRemoteState else { return }
        let track = TrackInfo(from: song)
        let audioPlayer = AudioPlayer.shared
        let queue = audioPlayer.queue.map { TrackInfo(from: $0) }
        let payload = PlaybackActionPayload(
            action: .changeTrack,
            trackId: song.id,
            position: 0,
            trackInfo: track,
            queue: queue,
            serverTime: Int64(Date().timeIntervalSince1970 * 1000)
        )
        Task {
            try? await client.send(type: "playback_action", payload: payload)
        }
    }

    func broadcastSeek(to time: Double) {
        guard isHost, isSessionActive, !isApplyingRemoteState else { return }
        let payload = PlaybackActionPayload(
            action: .seek,
            position: Int(time * 1000),
            serverTime: Int64(Date().timeIntervalSince1970 * 1000)
        )
        Task {
            try? await client.send(type: "playback_action", payload: payload)
        }
    }

    func broadcastQueueSync() {
        guard isHost, isSessionActive, !isApplyingRemoteState else { return }
        let audioPlayer = AudioPlayer.shared
        let queue = audioPlayer.queue.map { TrackInfo(from: $0) }
        let payload = PlaybackActionPayload(
            action: .syncQueue,
            queue: queue
        )
        Task {
            try? await client.send(type: "playback_action", payload: payload)
        }
    }

    // MARK: - Suggestions

    func suggestSong(_ song: Song) {
        guard isGuest, isSessionActive else { return }
        let track = TrackInfo(from: song)
        let payload = SuggestTrackPayload(trackInfo: track)
        Task {
            try? await client.send(type: "suggest_track", payload: payload)
        }
        Logger.log("Suggested song: \(song.title)", category: .sharePlay)
    }

    func acceptSuggestion(_ suggestion: SongSuggestion) {
        guard isHost else { return }
        pendingSuggestions.removeAll { $0.id == suggestion.id }
        let payload = ApproveSuggestionPayload(suggestionId: suggestion.id)
        Task {
            try? await client.send(type: "approve_suggestion", payload: payload)
        }
        let song = suggestion.track.toSong()
        Task {
            await AudioPlayer.shared.loadAndPlay(song: song)
        }
    }

    func rejectSuggestion(_ suggestion: SongSuggestion) {
        guard isHost else { return }
        pendingSuggestions.removeAll { $0.id == suggestion.id }
        let payload = RejectSuggestionPayload(suggestionId: suggestion.id)
        Task {
            try? await client.send(type: "reject_suggestion", payload: payload)
        }
    }

    // MARK: - Message Handling

    private func handleMessage(type: String, payload: Data) {
        let decoder = JSONDecoder()

        switch type {
        case "room_created":
            guard let p = try? decoder.decode(RoomCreatedPayload.self, from: payload) else { return }
            roomCode = p.roomCode
            userId = p.userId
            sessionToken = p.sessionToken
            role = .host
            isSessionActive = true
            participantCount = 1
            connectedUsers = [RoomUser(userId: p.userId, username: username, isHost: true)]
            connectionStatus = .connected
            startPeriodicSync()
            Task { await client.persistSession(token: p.sessionToken, roomCode: p.roomCode, userId: p.userId) }
            Logger.log("Room created: \(p.roomCode)", category: .sharePlay)

        case "join_request":
            guard let p = try? decoder.decode(JoinRequestPayload.self, from: payload) else { return }
            let request = JoinRequest(userId: p.userId, username: p.username)
            if !pendingJoinRequests.contains(where: { $0.userId == p.userId }) {
                pendingJoinRequests.append(request)
            }
            Logger.log("Join request from \(p.username)", category: .sharePlay)

        case "join_approved":
            guard let p = try? decoder.decode(JoinApprovedPayload.self, from: payload) else { return }
            roomCode = p.roomCode
            userId = p.userId
            sessionToken = p.sessionToken
            role = .guest
            isSessionActive = true
            connectionStatus = .connected
            if let state = p.state, let users = state.users {
                connectedUsers = users
                participantCount = users.count
            }
            Task { await client.persistSession(token: p.sessionToken, roomCode: p.roomCode, userId: p.userId) }
            // Request current state from host
            Task { try? await client.send(type: "request_sync") }
            Logger.log("Joined room: \(p.roomCode) as guest", category: .sharePlay)

        case "join_rejected":
            let p = try? decoder.decode(JoinRejectedPayload.self, from: payload)
            errorMessage = p?.reason ?? "Join request rejected"
            connectionStatus = .error
            Task { await client.disconnect() }
            Logger.log("Join rejected: \(p?.reason ?? "unknown")", category: .sharePlay)

        case "user_joined":
            guard let p = try? decoder.decode(UserJoinedPayload.self, from: payload) else { return }
            let user = RoomUser(userId: p.userId, username: p.username, isHost: false)
            if !connectedUsers.contains(where: { $0.userId == p.userId }) {
                connectedUsers.append(user)
            }
            participantCount = connectedUsers.count
            Logger.log("User joined: \(p.username)", category: .sharePlay)

        case "user_left":
            guard let p = try? decoder.decode(UserLeftPayload.self, from: payload) else { return }
            connectedUsers.removeAll { $0.userId == p.userId }
            participantCount = connectedUsers.count
            Logger.log("User left: \(p.username)", category: .sharePlay)

        case "sync_playback":
            guard let p = try? decoder.decode(SyncPlaybackPayload.self, from: payload) else { return }
            handleSyncPlayback(p)

        case "buffer_wait":
            Logger.log("Buffer wait received", category: .sharePlay)

        case "buffer_complete":
            Logger.log("Buffer complete — applying pending sync", category: .sharePlay)
            if let pending = pendingSyncPlayback {
                applySyncPlayback(pending)
                pendingSyncPlayback = nil
            }

        case "error":
            guard let p = try? decoder.decode(WSErrorPayload.self, from: payload) else { return }
            errorMessage = p.message
            Logger.error("Server error: \(p.message)", category: .sharePlay)

        case "pong":
            break // keep-alive acknowledged

        case "host_changed":
            guard let p = try? decoder.decode(HostChangedPayload.self, from: payload) else { return }
            if p.newHostId == userId {
                role = .host
                startPeriodicSync()
                Logger.log("You are now the host", category: .sharePlay)
            } else {
                role = .guest
                syncTimer?.invalidate()
                syncTimer = nil
            }
            // Update users list
            for i in connectedUsers.indices {
                connectedUsers[i] = RoomUser(
                    userId: connectedUsers[i].userId,
                    username: connectedUsers[i].username,
                    isHost: connectedUsers[i].userId == p.newHostId
                )
            }

        case "kicked":
            let p = try? decoder.decode(KickedPayload.self, from: payload)
            errorMessage = p?.reason ?? "You were removed from the room"
            cleanup()
            Task { await client.disconnect() }
            Logger.log("Kicked: \(p?.reason ?? "unknown")", category: .sharePlay)

        case "sync_state":
            guard let p = try? decoder.decode(SyncStatePayload.self, from: payload) else { return }
            if let track = p.currentTrack {
                isApplyingRemoteState = true
                let song = track.toSong()
                Task {
                    await AudioPlayer.shared.loadAndPlay(song: song)
                    if let position = p.position {
                        AudioPlayer.shared.seek(to: Double(position) / 1000.0)
                    }
                    if p.isPlaying == true {
                        AudioPlayer.shared.play()
                    } else {
                        AudioPlayer.shared.pause()
                    }
                    self.isApplyingRemoteState = false
                }
            }

        case "reconnected":
            guard let p = try? decoder.decode(ReconnectedPayload.self, from: payload) else { return }
            roomCode = p.roomCode
            userId = p.userId
            isSessionActive = true
            connectionStatus = .connected
            if p.isHost == true {
                role = .host
                startPeriodicSync()
            } else {
                role = .guest
            }
            if let state = p.state, let users = state.users {
                connectedUsers = users
                participantCount = users.count
            }
            Logger.log("Reconnected to room: \(p.roomCode)", category: .sharePlay)

        case "suggestion_received":
            guard let p = try? decoder.decode(SuggestionReceivedPayload.self, from: payload) else { return }
            let suggestion = SongSuggestion(
                id: p.suggestionId,
                track: p.trackInfo,
                suggestedBy: p.fromUsername,
                suggestedByUserId: p.fromUserId
            )
            if !pendingSuggestions.contains(where: { $0.id == p.suggestionId }) {
                pendingSuggestions.append(suggestion)
            }
            Logger.log("Suggestion: \(p.trackInfo.title) from \(p.fromUsername)", category: .sharePlay)

        case "suggestion_approved":
            guard let p = try? decoder.decode(SuggestionApprovedPayload.self, from: payload) else { return }
            pendingSuggestions.removeAll { $0.id == p.suggestionId }

        case "suggestion_rejected":
            guard let p = try? decoder.decode(SuggestionRejectedPayload.self, from: payload) else { return }
            pendingSuggestions.removeAll { $0.id == p.suggestionId }

        case "user_disconnected":
            guard let p = try? decoder.decode(UserDisconnectedPayload.self, from: payload) else { return }
            Logger.log("User disconnected: \(p.username)", category: .sharePlay)

        case "user_reconnected":
            guard let p = try? decoder.decode(UserReconnectedPayload.self, from: payload) else { return }
            Logger.log("User reconnected: \(p.username)", category: .sharePlay)

        default:
            Logger.log("Unknown message type: \(type)", category: .sharePlay)
        }
    }

    // MARK: - Playback Sync

    private func handleSyncPlayback(_ payload: SyncPlaybackPayload) {
        guard isGuest else { return }

        switch payload.action {
        case .changeTrack:
            guard let track = payload.trackInfo else { return }
            isApplyingRemoteState = true
            let song = track.toSong()
            // Store pending sync — apply after track loads and we send buffer_ready
            pendingSyncPlayback = payload
            Task {
                await AudioPlayer.shared.loadAndPlay(song: song)
                // Send buffer_ready to host
                let bufPayload = BufferReadyPayload(trackId: track.id)
                try? await client.send(type: "buffer_ready", payload: bufPayload)
                self.isApplyingRemoteState = false
            }

            // Update queue if provided
            if let queueTracks = payload.queue {
                let songs = queueTracks.map { $0.toSong() }
                AudioPlayer.shared.queue = songs
            }

        case .play, .pause:
            applySyncPlayback(payload)

        case .seek:
            isApplyingRemoteState = true
            if let position = payload.position {
                AudioPlayer.shared.seek(to: Double(position) / 1000.0)
            }
            isApplyingRemoteState = false

        case .syncQueue:
            if let queueTracks = payload.queue {
                isApplyingRemoteState = true
                let songs = queueTracks.map { $0.toSong() }
                AudioPlayer.shared.queue = songs
                isApplyingRemoteState = false
            }

        default:
            break
        }
    }

    private func applySyncPlayback(_ payload: SyncPlaybackPayload) {
        guard isGuest else { return }
        isApplyingRemoteState = true
        let audioPlayer = AudioPlayer.shared

        if let position = payload.position {
            var adjustedPositionMs = Double(position)
            // Latency compensation
            if let serverTime = payload.serverTime {
                let nowMs = Date().timeIntervalSince1970 * 1000
                adjustedPositionMs += (nowMs - Double(serverTime))
            }
            let seekTime = max(0, adjustedPositionMs / 1000.0)
            audioPlayer.seek(to: seekTime)
        }

        switch payload.action {
        case .play:
            audioPlayer.play()
        case .pause:
            audioPlayer.pause()
        default:
            break
        }

        isApplyingRemoteState = false
    }

    // MARK: - Periodic Sync

    private func startPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isHost, self.isSessionActive else { return }
                let audioPlayer = AudioPlayer.shared
                self.broadcastPlaybackState(
                    isPlaying: audioPlayer.isPlaying,
                    currentTime: audioPlayer.currentTime
                )
            }
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        syncTimer?.invalidate()
        syncTimer = nil
        isSessionActive = false
        role = .none
        participantCount = 0
        connectionStatus = .disconnected
        pendingSuggestions = []
        pendingJoinRequests = []
        connectedUsers = []
        roomCode = nil
        userId = nil
        sessionToken = nil
        errorMessage = nil
        isApplyingRemoteState = false
        pendingSyncPlayback = nil
    }
}

// MARK: - Actor callback helpers

extension ListenTogetherClient {
    func setCallbacks(
        onMessage: @escaping @Sendable (String, Data) -> Void,
        onStateChange: @escaping @Sendable (ConnectionState) -> Void
    ) {
        self.onMessage = onMessage
        self.onStateChange = onStateChange
    }
}
