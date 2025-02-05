import Foundation
import os

public final class SharedDataInteractor: SharedDataInteractorProtocol {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "SharedDataInteractor")
    private let maxCacheAge: TimeInterval = 15 * 60 // 15 minutes
    private let appGroupIdentifier = "group.genco"
    
    public init() {
        logger.notice("🔧 Initializing SharedDataInteractor...")
        
        // Debug app group access
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            logger.notice("📂 App group container path: \(containerURL.path)")
            
            // Create Preferences directory if it doesn't exist
            let prefsURL = containerURL.appendingPathComponent("Library/Preferences")
            do {
                try fileManager.createDirectory(at: prefsURL, withIntermediateDirectories: true)
                logger.notice("✅ Preferences directory ensured at: \(prefsURL.path)")
            } catch {
                logger.error("❌ Failed to create preferences directory: \(error.localizedDescription)")
            }
        } else {
            logger.error("❌ Could not access app group container")
        }
        
        logger.notice("✅ SharedDataInteractor initialized successfully")
    }
    
    @SharedDataActor
    public func saveWeatherData(_ data: CachedWeatherData) async throws {
        logger.notice("💾 Attempting to save weather data...")
        
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            logger.error("❌ Could not access app group container for saving")
            throw SharedDataError.saveFailed
        }
        
        let cacheFile = containerURL
            .appendingPathComponent("Library/Caches")
            .appendingPathComponent("weatherCache.json")
        
        do {
            let encoder = JSONEncoder()
            let encodedData = try encoder.encode(data)
            try encodedData.write(to: cacheFile, options: .atomic)
            logger.notice("✅ Successfully saved weather data. Items: \(data.weatherData.count), Size: \(encodedData.count) bytes")
        } catch {
            logger.error("❌ Failed to save weather data: \(error.localizedDescription)")
            throw SharedDataError.saveFailed
        }
    }
    
    @SharedDataActor
    public func loadWeatherData() async throws -> CachedWeatherData? {
        logger.notice("📂 Attempting to load weather data...")
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            logger.error("❌ Could not access app group container for loading")
            throw SharedDataError.loadFailed
        }
        
        let cacheFile = containerURL
            .appendingPathComponent("Library/Caches")
            .appendingPathComponent("weatherCache.json")
        
        guard fileManager.fileExists(atPath: cacheFile.path) else {
            logger.error("❌ No data found in shared cache")
            throw SharedDataError.cacheEmpty
        }
        
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            let cachedData = try decoder.decode(CachedWeatherData.self, from: data)
            
            let age = Date().timeIntervalSince(cachedData.timestamp)
            if age > maxCacheAge {
                logger.error("⏰ Cache is stale. Age: \(Int(age))s")
                throw SharedDataError.cacheStale
            }
            
            logger.notice("✅ Successfully loaded weather data. Items: \(cachedData.weatherData.count), Age: \(Int(age))s")
            return cachedData
        } catch {
            if error is SharedDataError { throw error }
            logger.error("❌ Failed to decode weather data: \(error.localizedDescription)")
            throw SharedDataError.loadFailed
        }
    }
    
    @SharedDataActor
    public func clearCache() async throws {
        logger.notice("🗑️ Clearing cache...")
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            logger.error("❌ Could not access app group container for clearing cache")
            return
        }
        
        let cacheFile = containerURL
            .appendingPathComponent("Library/Caches")
            .appendingPathComponent("weatherCache.json")
        
        do {
            try fileManager.removeItem(at: cacheFile)
            logger.notice("✅ Cache cleared")
        } catch {
            logger.error("❌ Failed to clear cache: \(error.localizedDescription)")
        }
    }
} 