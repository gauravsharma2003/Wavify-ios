//
//  CachedAsyncImage.swift
//  Wavify
//

import SwiftUI

struct CachedAsyncImagePhase<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    
    @State private var phase: AsyncImagePhase = .empty
    
    var body: some View {
        content(phase)
            .onAppear {
                // FAST SYNC CHECK: Check memory cache immediately on appear
                if let url = url,
                   let cached = ImageCache.shared.memoryCachedImage(for: url) {
                    phase = .success(Image(uiImage: cached))
                }
            }
            .task(id: url) {
                // Reset phase when URL changes to ensure we always load the new image
                phase = .empty
                
                // Quick sync check for memory cache before async load
                if let url = url,
                   let cached = ImageCache.shared.memoryCachedImage(for: url) {
                    phase = .success(Image(uiImage: cached))
                    return
                }
                
                await load()
            }
    }
    
    private func load() async {
        guard let url = url else {
            phase = .empty
            return
        }
        
        // Check full cache (memory + disk)
        if let cached = await ImageCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }
        
        // Load from network
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await ImageCache.shared.store(image, for: url)
                phase = .success(Image(uiImage: image))
            } else {
                phase = .failure(URLError(.badServerResponse))
            }
        } catch {
            phase = .failure(error)
        }
    }
}
