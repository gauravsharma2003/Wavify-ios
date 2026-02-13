//
//  ListenTogetherClient.swift
//  Wavify
//
//  WebSocket client for the Metrolist relay server.
//  Uses URLSessionWebSocketTask (built-in, no dependencies).
//

import Foundation
import Network

actor ListenTogetherClient {

    // MARK: - Types

    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var serverURL: URL?

    private(set) var state: ConnectionState = .disconnected

    /// Called on every decoded message (type, raw payload Data).
    var onMessage: (@Sendable (String, Data) -> Void)?

    /// Called when connection state changes.
    var onStateChange: (@Sendable (ConnectionState) -> Void)?

    // Reconnection
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 15
    private var reconnectTask: Task<Void, Never>?

    // Ping / pong
    private var pingTimer: Task<Void, Never>?

    // Network monitoring
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.wavify.networkMonitor")
    private var lastKnownNetworkAvailable = true

    // Session persistence keys
    private static let tokenKey = "listenTogether_token"
    private static let roomCodeKey = "listenTogether_roomCode"
    private static let userIdKey = "listenTogether_userId"
    private static let usernameKey = "listenTogether_username"

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connect / Disconnect

    func connect(to url: URL) {
        guard state == .disconnected || state == .reconnecting else { return }
        serverURL = url
        setState(.connecting)

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        reconnectAttempts = 0
        setState(.connected)
        startReceiveLoop()
        startPing()
        startNetworkMonitor()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTimer?.cancel()
        pingTimer = nil
        stopNetworkMonitor()

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        clearPersistedSession()
        setState(.disconnected)
    }

    // MARK: - Send

    /// Send a message with a typed payload (becomes nested JSON in the envelope).
    func send<T: Encodable>(type: String, payload: T) async throws {
        guard let task = webSocketTask else {
            throw URLError(.notConnectedToInternet)
        }

        let payloadData = try JSONEncoder().encode(payload)
        let payloadWrapper = AnyCodablePayload(payloadData)
        let envelope = WSEnvelope(type: type, payload: payloadWrapper)
        let data = try JSONEncoder().encode(envelope)
        let string = String(data: data, encoding: .utf8) ?? "{}"
        try await task.send(.string(string))
    }

    /// Send a message with no payload (e.g., ping, leave_room, request_sync).
    func send(type: String) async throws {
        guard let task = webSocketTask else {
            throw URLError(.notConnectedToInternet)
        }

        let envelope = WSEnvelope(type: type, payload: nil)
        let data = try JSONEncoder().encode(envelope)
        let string = String(data: data, encoding: .utf8) ?? "{}"
        try await task.send(.string(string))
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        guard let task = webSocketTask else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    await self?.handleMessage(message)
                } catch {
                    Logger.warning("WebSocket receive error: \(error.localizedDescription)", category: .sharePlay)
                    await self?.handleDisconnect()
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            data = Data(s.utf8)
        @unknown default:
            return
        }

        // Decode the envelope to get type + inner payload Data
        guard let envelope = try? JSONDecoder().decode(WSEnvelope.self, from: data) else {
            Logger.warning("Failed to decode WS envelope", category: .sharePlay)
            return
        }

        let payloadData = envelope.payload?.data ?? Data("{}".utf8)
        onMessage?(envelope.type, payloadData)
    }

    // MARK: - Ping

    private func startPing() {
        pingTimer?.cancel()
        pingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(25 * 1_000_000_000))
                guard !Task.isCancelled else { break }
                // Server ping has no payload
                try? await self?.send(type: "ping")
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        guard state != .disconnected else { return }
        webSocketTask = nil
        pingTimer?.cancel()
        setState(.reconnecting)
        attemptReconnect()
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts, let url = serverURL else {
            Logger.error("Max reconnect attempts reached", category: .sharePlay)
            setState(.disconnected)
            return
        }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            let attempt = await self.reconnectAttempts
            // Exponential backoff with jitter: min(2^attempt, 120) + random(0..2)
            let base = min(pow(2.0, Double(attempt)), 120.0)
            let jitter = Double.random(in: 0...2)
            let delay = base + jitter

            Logger.log("Reconnecting in \(String(format: "%.1f", delay))s (attempt \(attempt + 1))", category: .sharePlay)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await self.incrementReconnectAttempts()
            await self.performReconnect(url: url)
        }
    }

    private func incrementReconnectAttempts() {
        reconnectAttempts += 1
    }

    private func performReconnect(url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        reconnectAttempts = 0
        setState(.connected)
        startReceiveLoop()
        startPing()

        // If we have persisted session data, send a reconnect message
        if let token = persistedToken {
            let payload = ReconnectPayload(sessionToken: token)
            Task {
                try? await send(type: "reconnect", payload: payload)
            }
        }
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handlePathUpdate(satisfied: path.status == .satisfied)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func handlePathUpdate(satisfied: Bool) {
        if satisfied && !lastKnownNetworkAvailable && state == .reconnecting {
            Logger.log("Network restored, triggering reconnect", category: .sharePlay)
            reconnectAttempts = 0
            attemptReconnect()
        }
        lastKnownNetworkAvailable = satisfied
    }

    private func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - State

    private func setState(_ newState: ConnectionState) {
        state = newState
        onStateChange?(newState)
    }

    // MARK: - Session Persistence

    func persistSession(token: String, roomCode: String, userId: String) {
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        UserDefaults.standard.set(roomCode, forKey: Self.roomCodeKey)
        UserDefaults.standard.set(userId, forKey: Self.userIdKey)
    }

    func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.roomCodeKey)
        UserDefaults.standard.removeObject(forKey: Self.userIdKey)
    }

    var persistedToken: String? {
        UserDefaults.standard.string(forKey: Self.tokenKey)
    }

    var persistedRoomCode: String? {
        UserDefaults.standard.string(forKey: Self.roomCodeKey)
    }

    var persistedUserId: String? {
        UserDefaults.standard.string(forKey: Self.userIdKey)
    }

    // MARK: - Username Persistence

    static var persistedUsername: String {
        get { UserDefaults.standard.string(forKey: usernameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }
}
