//
//  LocationModels.swift
//  Wavify
//
//  Created by Wavify AI on 04/01/26.
//

import Foundation

struct UserLocation: Codable {
    let countryCode: String
    let country: String
    let region: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let pinCode: String?
    let timeZone: String?
    
    // Fallback location (Global/US)
    static var fallback: UserLocation {
        UserLocation(
            countryCode: "US",
            country: "United States",
            region: nil,
            city: nil,
            latitude: nil,
            longitude: nil,
            pinCode: nil,
            timeZone: nil
        )
    }
}

struct ChartResponse {
    let countryCharts: [SearchResult] // Top songs for the country
    let globalCharts: [SearchResult]  // Top songs global (filtered/extracted)
    let countryPlaylistId: String? // e.g. PL4fGSI1pDJn5oibdgJt8Hy0-dr2B7kSs2
    let globalParams: String?      // e.g. sgYPRkVtdXNpY19leHBsb3Jl
}
