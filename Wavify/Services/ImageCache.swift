
import SwiftUI

// Actor for thread-safe caching
actor ImageCache {
    static let shared = ImageCache()
    
    // Use a concurrent dictionary pattern for memory cache to avoid actor bottleneck
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL?
    
    // Config
    private let diskCacheLimit: Int = 200 * 1024 * 1024 // 200MB
    private let maxMemoryCount = 100
    
    init() {
        // Setup memory cache
        memoryCache.countLimit = maxMemoryCount
        
        // Setup disk cache
        if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let cacheDir = cacheURL.appendingPathComponent("WavifyImageCache")
            self.cacheDirectory = cacheDir
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            
            // Clean old files if needed (fire and forget with lower priority)
            Task.detached(priority: .background) { [weak self] in
                await self?.cleanDiskCache()
            }
        } else {
            self.cacheDirectory = nil
        }
    }
    
    /// Fast synchronous memory cache check - call from nonisolated context
    nonisolated func memoryCachedImage(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        return memoryCache.object(forKey: key)
    }
    
    /// Full cache check including disk
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        
        // 1. Check memory (fast)
        if let cachedImage = memoryCache.object(forKey: key) {
            return cachedImage
        }
        
        // 2. Check disk (async to avoid blocking)
        if let diskImage = await loadFromDisk(for: url) {
            // Populate memory cache
            memoryCache.setObject(diskImage, forKey: key)
            return diskImage
        }
        
        return nil
    }
    
    func store(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        
        // 1. Store in memory
        memoryCache.setObject(image, forKey: key)
        
        // 2. Store on disk (fire and forget)
        Task.detached(priority: .background) { [weak self] in
            await self?.saveToDisk(image, for: url)
        }
    }
    
    private func loadFromDisk(for url: URL) async -> UIImage? {
        guard let fileURL = diskFileURL(for: url) else { return nil }
        
        // Perform disk I/O on background thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let data = try? Data(contentsOf: fileURL),
                      let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
    
    private func saveToDisk(_ image: UIImage, for url: URL) {
        guard let fileURL = diskFileURL(for: url),
              let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        
        try? data.write(to: fileURL)
    }
    
    private func diskFileURL(for url: URL) -> URL? {
        guard let cacheDirectory = cacheDirectory else { return nil }
        
        // Simple hashing for filename
        let filename = String(url.absoluteString.hash)
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    private func cleanDiskCache() {
        guard let cacheDirectory = cacheDirectory,
              let resourceValues = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return
        }
        
        var totalSize: Int = 0
        var files: [(url: URL, size: Int, date: Date)] = []
        
        for fileURL in resourceValues {
            if let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
               let size = resources.fileSize,
               let date = resources.contentModificationDate {
                totalSize += size
                files.append((fileURL, size, date))
            }
        }
        
        if totalSize > diskCacheLimit {
            // Sort by oldest first
            files.sort { $0.date < $1.date }
            
            for file in files {
                if totalSize <= diskCacheLimit / 2 { break } // Clean up to 50%
                
                try? fileManager.removeItem(at: file.url)
                totalSize -= file.size
            }
        }
    }
    
    nonisolated func clearMemory() {
        memoryCache.removeAllObjects()
    }
    
    func clearAll() {
        memoryCache.removeAllObjects()
        
        if let cacheDirectory = cacheDirectory {
             try? fileManager.removeItem(at: cacheDirectory)
             try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
}
