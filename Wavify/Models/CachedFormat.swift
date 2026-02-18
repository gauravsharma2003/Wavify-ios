//
//  CachedFormat.swift
//  Wavify
//
//  SwiftData model for caching resolved audio stream URLs
//

import Foundation
import SwiftData

@Model
final class CachedFormat {
    @Attribute(.unique) var videoId: String
    var audioUrl: String
    var itag: Int
    var mimeType: String
    var bitrate: Int
    var playbackHeadersJSON: String
    var cpn: String
    var loudnessDb: Double?
    var expiresAt: Date
    var playbackTrackingUrl: String?
    var watchtimeTrackingUrl: String?
    var atrTrackingUrl: String?
    var cachedAt: Date

    init(
        videoId: String,
        audioUrl: String,
        itag: Int,
        mimeType: String,
        bitrate: Int,
        playbackHeadersJSON: String,
        cpn: String,
        loudnessDb: Double?,
        expiresAt: Date,
        playbackTrackingUrl: String?,
        watchtimeTrackingUrl: String?,
        atrTrackingUrl: String?,
        cachedAt: Date = Date()
    ) {
        self.videoId = videoId
        self.audioUrl = audioUrl
        self.itag = itag
        self.mimeType = mimeType
        self.bitrate = bitrate
        self.playbackHeadersJSON = playbackHeadersJSON
        self.cpn = cpn
        self.loudnessDb = loudnessDb
        self.expiresAt = expiresAt
        self.playbackTrackingUrl = playbackTrackingUrl
        self.watchtimeTrackingUrl = watchtimeTrackingUrl
        self.atrTrackingUrl = atrTrackingUrl
        self.cachedAt = cachedAt
    }
}
