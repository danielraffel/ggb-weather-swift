import Foundation
import os
import WatchConnectivity
import WidgetKit

private extension ProcessInfo {
    var isWatchOS: Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }
}

public final class SharedDataInteractor: NSObject, SharedDataInteractorProtocol, WCSessionDelegate {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "SharedDataInteractor")
    private let maxCacheAge: TimeInterval = 15 * 60 // 15 minutes
    private let appGroupIdentifier = "group.genco"
    private let sharedDefaults: UserDefaults?
    private var session: WCSession?
    
    public override init() {
        self.sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        super.init()
        
        if WCSession.isSupported() {
            self.session = WCSession.default
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        
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
    
    // Required WCSessionDelegate methods
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("❌ WCSession activation failed: \(error.localizedDescription)")
        } else {
            logger.notice("✅ WCSession activated with state: \(activationState.rawValue)")
        }
    }
    
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
        logger.notice("⚠️ WCSession became inactive")
    }
    
    public func sessionDidDeactivate(_ session: WCSession) {
        logger.notice("⚠️ WCSession deactivated")
        WCSession.default.activate()
    }
    #endif
    
    // SharedDataInteractorProtocol methods
    @SharedDataActor
    public func saveWeatherData(_ data: CachedWeatherData) async throws {
        logger.notice("📂 Saving weather data...")
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let cacheURL = containerURL.appendingPathComponent("Library/Caches/weatherData.json")
            let encoder = JSONEncoder()
            let data = try encoder.encode(data)
            try data.write(to: cacheURL)
            logger.notice("✅ Saved weather data to cache")
            
            // Also save to UserDefaults as backup
            sharedDefaults?.set(data, forKey: "weatherData")
            logger.notice("✅ Saved weather data to UserDefaults")
            
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            logger.error("❌ Could not access app group container")
            throw SharedDataError.saveFailed
        }
    }
    
    @SharedDataActor
    public func loadWeatherData() async throws -> CachedWeatherData? {
        logger.notice("📂 Attempting to load weather data...")
        
        // Try loading from UserDefaults first
        if let data = sharedDefaults?.data(forKey: "weatherData") {
            do {
                let decoder = JSONDecoder()
                let weatherData = try decoder.decode(CachedWeatherData.self, from: data)
                logger.notice("✅ Loaded weather data from UserDefaults")
                return weatherData
            } catch {
                logger.error("❌ Failed to decode UserDefaults data: \(error)")
            }
        }
        
        // Try loading from file cache
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let cacheURL = containerURL.appendingPathComponent("Library/Caches/weatherData.json")
            do {
                let data = try Data(contentsOf: cacheURL)
                let decoder = JSONDecoder()
                let weatherData = try decoder.decode(CachedWeatherData.self, from: data)
                logger.notice("✅ Loaded weather data from file cache")
                return weatherData
            } catch {
                logger.error("❌ Failed to load from file cache: \(error)")
            }
        }
        
        logger.error("❌ No data found in shared cache")
        return nil
    }
    
    @SharedDataActor
    public func clearCache() async throws {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let cacheURL = containerURL.appendingPathComponent("Library/Caches/weatherData.json")
            try? fileManager.removeItem(at: cacheURL)
            sharedDefaults?.removeObject(forKey: "weatherData")
            logger.notice("✅ Cleared weather data cache")
        }
    }
} 