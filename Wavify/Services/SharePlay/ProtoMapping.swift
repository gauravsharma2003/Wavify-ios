//
//  ProtoMapping.swift
//  Wavify
//
//  Bidirectional bridge between protobuf wire types (LT_*) and the existing
//  Codable types used by SharePlayManager. Produces/consumes JSON Data so
//  SharePlayManager needs zero changes.
//

import Foundation
import SwiftProtobuf

nonisolated enum ProtoMapping {

    // MARK: - Incoming: Protobuf → JSON Data

    static func toJSON(type: String, protoPayload: Data) -> Data {
        do {
            switch type {
            case "room_created":
                let pb = try LT_RoomCreatedPayload(serializedData: protoPayload)
                return json([
                    "room_code": pb.roomCode,
                    "user_id": pb.userID,
                    "session_token": pb.sessionToken
                ])

            case "join_request":
                let pb = try LT_JoinRequestPayload(serializedData: protoPayload)
                return json([
                    "user_id": pb.userID,
                    "username": pb.username
                ])

            case "join_approved":
                let pb = try LT_JoinApprovedPayload(serializedData: protoPayload)
                var dict: [String: Any] = [
                    "room_code": pb.roomCode,
                    "user_id": pb.userID,
                    "session_token": pb.sessionToken
                ]
                if pb.hasState {
                    dict["state"] = roomStateDict(pb.state)
                }
                return json(dict)

            case "join_rejected":
                let pb = try LT_JoinRejectedPayload(serializedData: protoPayload)
                return json(nonEmpty(["reason": pb.reason]))

            case "user_joined":
                let pb = try LT_UserJoinedPayload(serializedData: protoPayload)
                return json(["user_id": pb.userID, "username": pb.username])

            case "user_left":
                let pb = try LT_UserLeftPayload(serializedData: protoPayload)
                return json(["user_id": pb.userID, "username": pb.username])

            case "sync_playback":
                let pb = try LT_PlaybackActionPayload(serializedData: protoPayload)
                return json(playbackActionDict(pb))

            case "buffer_wait":
                let pb = try LT_BufferWaitPayload(serializedData: protoPayload)
                var dict: [String: Any] = [:]
                if !pb.trackID.isEmpty { dict["track_id"] = pb.trackID }
                if !pb.waitingFor.isEmpty { dict["waiting_for"] = pb.waitingFor }
                return json(dict)

            case "buffer_complete":
                let pb = try LT_BufferCompletePayload(serializedData: protoPayload)
                var dict: [String: Any] = [:]
                if !pb.trackID.isEmpty { dict["track_id"] = pb.trackID }
                return json(dict)

            case "error":
                let pb = try LT_ErrorPayload(serializedData: protoPayload)
                var dict: [String: Any] = ["message": pb.message]
                if !pb.code.isEmpty { dict["code"] = pb.code }
                return json(dict)

            case "pong":
                return json([:])

            case "host_changed":
                let pb = try LT_HostChangedPayload(serializedData: protoPayload)
                return json([
                    "new_host_id": pb.newHostID,
                    "new_host_name": pb.newHostName
                ])

            case "kicked":
                let pb = try LT_KickedPayload(serializedData: protoPayload)
                return json(nonEmpty(["reason": pb.reason]))

            case "sync_state":
                let pb = try LT_SyncStatePayload(serializedData: protoPayload)
                var dict: [String: Any] = [:]
                if pb.hasCurrentTrack { dict["current_track"] = trackInfoDict(pb.currentTrack) }
                if pb.isPlaying { dict["is_playing"] = true }
                if pb.position != 0 { dict["position"] = pb.position }
                if pb.lastUpdate != 0 { dict["last_update"] = pb.lastUpdate }
                if pb.volume != 0 { dict["volume"] = pb.volume }
                return json(dict)

            case "reconnected":
                let pb = try LT_ReconnectedPayload(serializedData: protoPayload)
                var dict: [String: Any] = [
                    "room_code": pb.roomCode,
                    "user_id": pb.userID
                ]
                if pb.hasState { dict["state"] = roomStateDict(pb.state) }
                if pb.isHost { dict["is_host"] = true }
                return json(dict)

            case "user_reconnected":
                let pb = try LT_UserReconnectedPayload(serializedData: protoPayload)
                return json(["user_id": pb.userID, "username": pb.username])

            case "user_disconnected":
                let pb = try LT_UserDisconnectedPayload(serializedData: protoPayload)
                return json(["user_id": pb.userID, "username": pb.username])

            case "suggestion_received":
                let pb = try LT_SuggestionReceivedPayload(serializedData: protoPayload)
                var dict: [String: Any] = [
                    "suggestion_id": pb.suggestionID,
                    "from_user_id": pb.fromUserID,
                    "from_username": pb.fromUsername
                ]
                if pb.hasTrackInfo { dict["track_info"] = trackInfoDict(pb.trackInfo) }
                return json(dict)

            case "suggestion_approved":
                let pb = try LT_SuggestionApprovedPayload(serializedData: protoPayload)
                var dict: [String: Any] = ["suggestion_id": pb.suggestionID]
                if pb.hasTrackInfo { dict["track_info"] = trackInfoDict(pb.trackInfo) }
                return json(dict)

            case "suggestion_rejected":
                let pb = try LT_SuggestionRejectedPayload(serializedData: protoPayload)
                var dict: [String: Any] = ["suggestion_id": pb.suggestionID]
                if !pb.reason.isEmpty { dict["reason"] = pb.reason }
                return json(dict)

            default:
                return json([:])
            }
        } catch {
            Logger.warning("ProtoMapping.toJSON failed for '\(type)': \(error.localizedDescription)", category: .sharePlay)
            return Data("{}".utf8)
        }
    }

    // MARK: - Outgoing: JSON Data → Protobuf Message

    static func toProto(type: String, jsonPayload: Data) -> (any SwiftProtobuf.Message)? {
        do {
            switch type {
            case "create_room":
                let p = try JSONDecoder().decode(CreateRoomPayload.self, from: jsonPayload)
                var pb = LT_CreateRoomPayload()
                pb.username = p.username
                return pb

            case "join_room":
                let p = try JSONDecoder().decode(JoinRoomPayload.self, from: jsonPayload)
                var pb = LT_JoinRoomPayload()
                pb.roomCode = p.roomCode
                pb.username = p.username
                return pb

            case "approve_join":
                let p = try JSONDecoder().decode(ApproveJoinPayload.self, from: jsonPayload)
                var pb = LT_ApproveJoinPayload()
                pb.userID = p.userId
                return pb

            case "reject_join":
                let p = try JSONDecoder().decode(RejectJoinPayload.self, from: jsonPayload)
                var pb = LT_RejectJoinPayload()
                pb.userID = p.userId
                if let reason = p.reason { pb.reason = reason }
                return pb

            case "playback_action":
                let p = try JSONDecoder().decode(PlaybackActionPayload.self, from: jsonPayload)
                var pb = LT_PlaybackActionPayload()
                pb.action = p.action.rawValue
                if let trackId = p.trackId { pb.trackID = trackId }
                if let position = p.position { pb.position = Int64(position) }
                if let trackInfo = p.trackInfo { pb.trackInfo = trackInfoToProto(trackInfo) }
                if let insertNext = p.insertNext { pb.insertNext = insertNext }
                if let q = p.queue { pb.queue = q.map { trackInfoToProto($0) } }
                if let qt = p.queueTitle { pb.queueTitle = qt }
                if let volume = p.volume { pb.volume = volume }
                if let serverTime = p.serverTime { pb.serverTime = serverTime }
                return pb

            case "buffer_ready":
                let p = try JSONDecoder().decode(BufferReadyPayload.self, from: jsonPayload)
                var pb = LT_BufferReadyPayload()
                pb.trackID = p.trackId
                return pb

            case "suggest_track":
                let p = try JSONDecoder().decode(SuggestTrackPayload.self, from: jsonPayload)
                var pb = LT_SuggestTrackPayload()
                pb.trackInfo = trackInfoToProto(p.trackInfo)
                return pb

            case "approve_suggestion":
                let p = try JSONDecoder().decode(ApproveSuggestionPayload.self, from: jsonPayload)
                var pb = LT_ApproveSuggestionPayload()
                pb.suggestionID = p.suggestionId
                return pb

            case "reject_suggestion":
                let p = try JSONDecoder().decode(RejectSuggestionPayload.self, from: jsonPayload)
                var pb = LT_RejectSuggestionPayload()
                pb.suggestionID = p.suggestionId
                if let reason = p.reason { pb.reason = reason }
                return pb

            case "reconnect":
                let p = try JSONDecoder().decode(ReconnectPayload.self, from: jsonPayload)
                var pb = LT_ReconnectPayload()
                pb.sessionToken = p.sessionToken
                return pb

            case "leave_room", "request_sync", "ping":
                return nil

            default:
                Logger.warning("ProtoMapping.toProto: unknown type '\(type)'", category: .sharePlay)
                return nil
            }
        } catch {
            Logger.warning("ProtoMapping.toProto failed for '\(type)': \(error.localizedDescription)", category: .sharePlay)
            return nil
        }
    }

    // MARK: - Helpers

    private static func json(_ dict: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
    }

    private static func nonEmpty(_ dict: [String: String]) -> [String: Any] {
        dict.filter { !$0.value.isEmpty }
    }

    private static func trackInfoDict(_ pb: LT_TrackInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "id": pb.id,
            "title": pb.title,
            "artist": pb.artist,
            "duration": pb.duration
        ]
        if !pb.album.isEmpty { dict["album"] = pb.album }
        if !pb.thumbnail.isEmpty { dict["thumbnail"] = pb.thumbnail }
        return dict
    }

    private static func trackInfoToProto(_ t: TrackInfo) -> LT_TrackInfo {
        var pb = LT_TrackInfo()
        pb.id = t.id
        pb.title = t.title
        pb.artist = t.artist
        if let album = t.album { pb.album = album }
        pb.duration = Int64(t.duration)
        if let thumbnail = t.thumbnail { pb.thumbnail = thumbnail }
        return pb
    }

    private static func userInfoDict(_ pb: LT_UserInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "user_id": pb.userID,
            "username": pb.username,
            "is_host": pb.isHost
        ]
        if pb.isConnected { dict["is_connected"] = true }
        return dict
    }

    private static func roomStateDict(_ pb: LT_RoomState) -> [String: Any] {
        var dict: [String: Any] = [:]
        if !pb.roomCode.isEmpty { dict["room_code"] = pb.roomCode }
        if !pb.hostID.isEmpty { dict["host_id"] = pb.hostID }
        if !pb.users.isEmpty { dict["users"] = pb.users.map { userInfoDict($0) } }
        if pb.hasCurrentTrack { dict["current_track"] = trackInfoDict(pb.currentTrack) }
        if pb.isPlaying { dict["is_playing"] = true }
        if pb.position != 0 { dict["position"] = pb.position }
        if pb.lastUpdate != 0 { dict["last_update"] = pb.lastUpdate }
        if pb.volume != 0 { dict["volume"] = pb.volume }
        if !pb.queue.isEmpty { dict["queue"] = pb.queue.map { trackInfoDict($0) } }
        return dict
    }

    private static func playbackActionDict(_ pb: LT_PlaybackActionPayload) -> [String: Any] {
        var dict: [String: Any] = ["action": pb.action]
        if !pb.trackID.isEmpty { dict["track_id"] = pb.trackID }
        if pb.position != 0 { dict["position"] = pb.position }
        if pb.hasTrackInfo { dict["track_info"] = trackInfoDict(pb.trackInfo) }
        if pb.insertNext { dict["insert_next"] = true }
        if !pb.queue.isEmpty { dict["queue"] = pb.queue.map { trackInfoDict($0) } }
        if !pb.queueTitle.isEmpty { dict["queue_title"] = pb.queueTitle }
        if pb.volume != 0 { dict["volume"] = pb.volume }
        if pb.serverTime != 0 { dict["server_time"] = pb.serverTime }
        return dict
    }
}
