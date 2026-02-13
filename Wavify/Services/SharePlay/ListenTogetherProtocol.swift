//
//  ListenTogetherProtocol.swift
//  Wavify
//
//  Codable message types for the Metrolist WebSocket relay protocol.
//  Server: wss://metroserver.meowery.eu/ws
//  Wire format: JSON envelopes  {"type": "...", "payload": {...}}
//  Note: payload is a raw JSON object, NOT a JSON-encoded string.
//

import Foundation

// MARK: - Envelope

/// Every message on the wire is wrapped in this envelope.
/// The server uses `json.RawMessage` for payload, so it's a nested JSON object.
struct WSEnvelope: Codable {
    let type: String
    let payload: AnyCodablePayload?
}

/// Wrapper for encoding/decoding raw JSON payloads within the envelope.
struct AnyCodablePayload: Codable {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    init<T: Encodable>(_ value: T) throws {
        self.data = try JSONEncoder().encode(value)
    }

    init(from decoder: Decoder) throws {
        // Capture the raw JSON from the container
        let container = try decoder.singleValueContainer()
        // Decode as generic JSON value and re-encode to Data
        let jsonValue = try container.decode(JSONValue.self)
        self.data = try JSONEncoder().encode(jsonValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let jsonValue = try JSONDecoder().decode(JSONValue.self, from: data)
        try container.encode(jsonValue)
    }
}

/// Generic JSON value for pass-through encoding/decoding.
private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Track Info (replaces SharePlaySong)

struct TrackInfo: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    var album: String?
    let duration: Int           // milliseconds (server uses ms)
    var thumbnail: String?

    init(from song: Song) {
        self.id = song.id
        self.title = song.title
        self.artist = song.artist
        self.album = nil
        // Convert song.duration (seconds string) to milliseconds
        self.duration = Int((Double(song.duration) ?? 0) * 1000)
        self.thumbnail = song.thumbnailUrl
    }

    func toSong() -> Song {
        Song(
            id: id,
            title: title,
            artist: artist,
            thumbnailUrl: thumbnail ?? "",
            duration: "\(duration / 1000)",
            artistId: nil,
            albumId: nil
        )
    }
}

// MARK: - Playback Action

enum PlaybackAction: String, Codable {
    case play
    case pause
    case seek
    case changeTrack = "change_track"
    case skipNext = "skip_next"
    case skipPrev = "skip_prev"
    case queueAdd = "queue_add"
    case queueRemove = "queue_remove"
    case queueClear = "queue_clear"
    case syncQueue = "sync_queue"
    case setVolume = "set_volume"
}

// MARK: - Room User

struct RoomUser: Codable, Identifiable, Hashable {
    let userId: String
    let username: String
    var isHost: Bool
    var isConnected: Bool?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case isHost = "is_host"
        case isConnected = "is_connected"
    }
}

// MARK: - Join Request

struct JoinRequest: Codable, Identifiable {
    let userId: String
    let username: String

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
    }
}

// MARK: - Song Suggestion

struct SongSuggestion: Identifiable {
    let id: String
    let track: TrackInfo
    let suggestedBy: String
    let suggestedByUserId: String
}

// MARK: - Client → Server Payloads

struct CreateRoomPayload: Codable {
    let username: String
}

struct JoinRoomPayload: Codable {
    let roomCode: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case roomCode = "room_code"
        case username
    }
}

// leave_room has no payload (empty object or nil)
struct EmptyPayload: Codable {}

struct ApproveJoinPayload: Codable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct RejectJoinPayload: Codable {
    let userId: String
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case reason
    }
}

struct PlaybackActionPayload: Codable {
    let action: PlaybackAction
    var trackId: String?
    var position: Int?          // milliseconds
    var trackInfo: TrackInfo?
    var insertNext: Bool?
    var queue: [TrackInfo]?
    var queueTitle: String?
    var volume: Float?
    var serverTime: Int64?      // epoch ms

    enum CodingKeys: String, CodingKey {
        case action
        case trackId = "track_id"
        case position
        case trackInfo = "track_info"
        case insertNext = "insert_next"
        case queue
        case queueTitle = "queue_title"
        case volume
        case serverTime = "server_time"
    }
}

struct BufferReadyPayload: Codable {
    let trackId: String

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
    }
}

struct SuggestTrackPayload: Codable {
    let trackInfo: TrackInfo

    enum CodingKeys: String, CodingKey {
        case trackInfo = "track_info"
    }
}

struct ApproveSuggestionPayload: Codable {
    let suggestionId: String

    enum CodingKeys: String, CodingKey {
        case suggestionId = "suggestion_id"
    }
}

struct RejectSuggestionPayload: Codable {
    let suggestionId: String
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case suggestionId = "suggestion_id"
        case reason
    }
}

// request_sync and ping have no payload

struct ReconnectPayload: Codable {
    let sessionToken: String

    enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
    }
}

// MARK: - Server → Client Payloads

struct RoomCreatedPayload: Codable {
    let roomCode: String
    let userId: String
    let sessionToken: String

    enum CodingKeys: String, CodingKey {
        case roomCode = "room_code"
        case userId = "user_id"
        case sessionToken = "session_token"
    }
}

struct JoinRequestPayload: Codable {
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
    }
}

struct RoomState: Codable {
    var roomCode: String?
    var hostId: String?
    var users: [RoomUser]?
    var currentTrack: TrackInfo?
    var isPlaying: Bool?
    var position: Int?
    var lastUpdate: Int64?
    var volume: Float?
    var queue: [TrackInfo]?

    enum CodingKeys: String, CodingKey {
        case roomCode = "room_code"
        case hostId = "host_id"
        case users
        case currentTrack = "current_track"
        case isPlaying = "is_playing"
        case position
        case lastUpdate = "last_update"
        case volume
        case queue
    }
}

struct JoinApprovedPayload: Codable {
    let roomCode: String
    let userId: String
    let sessionToken: String
    var state: RoomState?

    enum CodingKeys: String, CodingKey {
        case roomCode = "room_code"
        case userId = "user_id"
        case sessionToken = "session_token"
        case state
    }
}

struct JoinRejectedPayload: Codable {
    var reason: String?
}

struct UserJoinedPayload: Codable {
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
    }
}

struct UserLeftPayload: Codable {
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
    }
}

struct SyncPlaybackPayload: Codable {
    let action: PlaybackAction
    var trackId: String?
    var position: Int?
    var trackInfo: TrackInfo?
    var queue: [TrackInfo]?
    var serverTime: Int64?
    var volume: Float?

    enum CodingKeys: String, CodingKey {
        case action
        case trackId = "track_id"
        case position
        case trackInfo = "track_info"
        case queue
        case serverTime = "server_time"
        case volume
    }
}

struct BufferWaitPayload: Codable {
    var trackId: String?
    var waitingFor: [String]?

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case waitingFor = "waiting_for"
    }
}

struct BufferCompletePayload: Codable {
    var trackId: String?

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
    }
}

struct WSErrorPayload: Codable {
    let message: String
    var code: String?
}

// pong has no payload

struct HostChangedPayload: Codable {
    let newHostId: String
    let newHostName: String

    enum CodingKeys: String, CodingKey {
        case newHostId = "new_host_id"
        case newHostName = "new_host_name"
    }
}

struct KickedPayload: Codable {
    var reason: String?
}

struct SyncStatePayload: Codable {
    var currentTrack: TrackInfo?
    var isPlaying: Bool?
    var position: Int?
    var lastUpdate: Int64?
    var volume: Float?

    enum CodingKeys: String, CodingKey {
        case currentTrack = "current_track"
        case isPlaying = "is_playing"
        case position
        case lastUpdate = "last_update"
        case volume
    }
}

struct ReconnectedPayload: Codable {
    let roomCode: String
    let userId: String
    var state: RoomState?
    var isHost: Bool?

    enum CodingKeys: String, CodingKey {
        case roomCode = "room_code"
        case userId = "user_id"
        case state
        case isHost = "is_host"
    }
}

struct SuggestionReceivedPayload: Codable {
    let suggestionId: String
    let fromUserId: String
    let fromUsername: String
    let trackInfo: TrackInfo

    enum CodingKeys: String, CodingKey {
        case suggestionId = "suggestion_id"
        case fromUserId = "from_user_id"
        case fromUsername = "from_username"
        case trackInfo = "track_info"
    }
}

struct SuggestionApprovedPayload: Codable {
    let suggestionId: String
    var trackInfo: TrackInfo?

    enum CodingKeys: String, CodingKey {
        case suggestionId = "suggestion_id"
        case trackInfo = "track_info"
    }
}

struct SuggestionRejectedPayload: Codable {
    let suggestionId: String
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case suggestionId = "suggestion_id"
        case reason
    }
}

struct UserDisconnectedPayload: Codable {
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
    }
}

struct UserReconnectedPayload: Codable {
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
    }
}
