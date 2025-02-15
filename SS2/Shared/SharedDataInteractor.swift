import Foundation
import os
import WidgetKit

public protocol SharedDataInteractorProtocol {
    func saveWeatherData(_ data: CachedWeatherData) async throws
    func loadWeatherData(maxRetries: Int, retryDelay: TimeInterval) async throws -> CachedWeatherData?
    func clearCache() async throws
}

public final class SharedDataInteractor: SharedDataInteractorProtocol {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "SharedDataInteractor")
    private let maxCacheAge: TimeInterval = 15 * 60 // 15 minutes
    private let appGroupIdentifier = "group.genco"
    private let sharedDefaults: UserDefaults?
    private var cachedContainers: [URL]?
    
    public init() {
        self.sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
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
        }
        
        logger.notice("✅ SharedDataInteractor initialized successfully")
    }
    
    @SharedDataActor
    public func saveWeatherData(_ data: CachedWeatherData) async throws {
        logger.notice("💾 Attempting to save weather data...")
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(data)
        
        var savedSuccessfully = false
        let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
        
        for containerURL in getContainerURLs() {
            // Save to both Preferences and Caches directories
            let prefsDir = containerURL.appendingPathComponent("Library/Preferences")
            let cachesDir = containerURL.appendingPathComponent("Library/Caches")
            let savePaths = [
                prefsDir.appendingPathComponent("weatherCache.json"),
                cachesDir.appendingPathComponent("weatherCache.json")
            ]
            
            for savePath in savePaths {
                do {
                    try fileManager.createDirectory(at: savePath.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try encodedData.write(to: savePath, options: .atomic)
                    
                    if let size = try? savePath.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        logger.notice("✅ Successfully saved weather data to \(savePath.path). Items: \(data.weatherData.count), Size: \(size) bytes")
                        savedSuccessfully = true
                    }
                } catch {
                    logger.error("❌ Failed to save to cache at \(savePath.path): \(error)")
                    // Only throw error if this is the last container and we haven't saved successfully
                    if !isSimulator || containerURL == getContainerURLs().last {
                        if !savedSuccessfully {
                            throw SharedDataError.saveFailed
                        }
                    }
                }
            }
        }
        
        if !savedSuccessfully {
            throw SharedDataError.saveFailed
        }
    }
    
    @SharedDataActor
    public func loadWeatherData(maxRetries: Int = 3, retryDelay: TimeInterval = 2.0) async throws -> CachedWeatherData? {
        // Try loading from UserDefaults first
        if let data = try await self.loadFromUserDefaults() {
            logger.notice("✅ Found data in UserDefaults")
            return data
        }
        
        // Then try file cache
        if let data = try await self.loadFromFileCache() {
            logger.notice("✅ Found data in file cache")
            return data
        }
        
        logger.error("❌ No data found in shared cache or from iOS app")
        throw SharedDataError.cacheEmpty
    }
    
    private func loadFromUserDefaults() async throws -> CachedWeatherData? {
        logger.notice("📱 Attempting to load from UserDefaults...")
        guard let sharedDefaults = UserDefaults(suiteName: self.appGroupIdentifier) else {
            logger.error("❌ Could not access shared UserDefaults")
            return nil
        }
        
        // Try both keys for compatibility
        let keys = ["weatherData", "cachedWeatherData"]
        for key in keys {
            if let encodedData = sharedDefaults.data(forKey: key) {
                let decoder = JSONDecoder()
                let cachedData = try decoder.decode(CachedWeatherData.self, from: encodedData)
                logger.notice("✅ Loaded from UserDefaults with key: \(key)")
                return cachedData
            }
        }
        return nil
    }
    
    private func loadFromFileCache() async throws -> CachedWeatherData? {
        logger.notice("📂 Attempting to load weather data...")
        
        for containerURL in getContainerURLs() {
            // Try both Preferences and Caches directories
            let prefsURL = containerURL.appendingPathComponent("Library/Preferences")
            let cachesURL = containerURL.appendingPathComponent("Library/Caches")
            let possiblePaths = [
                prefsURL.appendingPathComponent("weatherCache.json"),
                cachesURL.appendingPathComponent("weatherCache.json")
            ]
            
            for cacheFile in possiblePaths {
                if fileManager.fileExists(atPath: cacheFile.path),
                   let data = try? Data(contentsOf: cacheFile),
                   let cachedData = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                    
                    let age = Date().timeIntervalSince(cachedData.timestamp)
                    if age <= maxCacheAge {
                        logger.notice("✅ Found valid cache at: \(cacheFile.path)")
                        return cachedData
                    } else {
                        logger.notice("⚠️ Cache expired at: \(cacheFile.path)")
                    }
                }
            }
        }
        
        logger.error("❌ No data found in shared cache")
        return nil
    }
    
    private func getContainerURLs() -> [URL] {
        // Return cached containers if available
        if let cached = cachedContainers {
            return cached
        }
        
        var containers: [URL] = []
        let appGroupIdentifiers = ["group.genco", "group.generouscorp.ggb"]
        let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
        
        logger.notice("🔍 Running on \(isSimulator ? "simulator" : "physical device")")
        
        // Try all possible app group identifiers
        for identifier in appGroupIdentifiers {
            if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                containers.append(containerURL)
                logger.notice("📂 Found container for \(identifier): \(containerURL.path)")
                
                // In simulator, we need to look for additional containers
                if isSimulator {
                    // Get simulator root directory (6 levels up from container)
                    let simulatorRoot = containerURL.deletingLastPathComponent() // AppGroup
                        .deletingLastPathComponent() // Shared
                        .deletingLastPathComponent() // Containers
                        .deletingLastPathComponent() // data
                        .deletingLastPathComponent() // DeviceID
                        .deletingLastPathComponent() // Devices
                    
                    logger.notice("�� Simulator root: \(simulatorRoot.path)")
                    
                    // Look for app group containers in all simulator devices
                    if let deviceDirs = try? fileManager.contentsOfDirectory(at: simulatorRoot, includingPropertiesForKeys: nil) {
                        for deviceDir in deviceDirs where deviceDir.hasDirectoryPath {
                            let appGroupPath = deviceDir.appendingPathComponent("data/Containers/Shared/AppGroup")
                            if let appGroups = try? fileManager.contentsOfDirectory(at: appGroupPath, includingPropertiesForKeys: nil) {
                                for group in appGroups where group.hasDirectoryPath {
                                    // Check if this is our app group by looking for our cache file
                                    let prefsPath = group.appendingPathComponent("Library/Preferences/weatherCache.json")
                                    let cachesPath = group.appendingPathComponent("Library/Caches/weatherCache.json")
                                    
                                    if fileManager.fileExists(atPath: prefsPath.path) || fileManager.fileExists(atPath: cachesPath.path) {
                                        if !containers.contains(group) {
                                            containers.append(group)
                                            logger.notice("✅ Found additional container in simulator: \(group.path)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // If we're on a physical device and no containers were found, try to create one
        if containers.isEmpty && !isSimulator {
            if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
                containers.append(containerURL)
                logger.notice("📂 Created new container on physical device: \(containerURL.path)")
                
                // Ensure the Preferences directory exists
                let prefsURL = containerURL.appendingPathComponent("Library/Preferences")
                do {
                    try fileManager.createDirectory(at: prefsURL, withIntermediateDirectories: true)
                    logger.notice("✅ Created Preferences directory at: \(prefsURL.path)")
                } catch {
                    logger.error("❌ Failed to create Preferences directory: \(error.localizedDescription)")
                }
            }
        }
        
        // Log all found containers
        logger.notice("📱 Found \(containers.count) potential app group containers")
        for (index, container) in containers.enumerated() {
            logger.notice("   📂 [\(index + 1)] \(container.path)")
            
            // Check for existing cache files
            let prefsPath = container.appendingPathComponent("Library/Preferences/weatherCache.json")
            let cachesPath = container.appendingPathComponent("Library/Caches/weatherCache.json")
            
            if fileManager.fileExists(atPath: prefsPath.path) {
                if let data = try? Data(contentsOf: prefsPath),
                   let cachedData = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                    logger.notice("      ✅ Valid cache in Preferences: \(cachedData.weatherData.count) items")
                }
            }
            
            if fileManager.fileExists(atPath: cachesPath.path) {
                if let data = try? Data(contentsOf: cachesPath),
                   let cachedData = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                    logger.notice("      ✅ Valid cache in Caches: \(cachedData.weatherData.count) items")
                }
            }
        }
        
        // Cache the containers for future use
        cachedContainers = containers
        return containers
    }
    
    @SharedDataActor
    public func clearCache() async throws {
        logger.notice("🗑️ Clearing cache...")
        
        // Clear UserDefaults
        if let sharedDefaults = sharedDefaults {
            sharedDefaults.removeObject(forKey: "cachedWeatherData")
            sharedDefaults.synchronize()
            logger.notice("✅ Cleared UserDefaults cache")
        }
        
        // Clear file cache from all potential containers
        for containerURL in getContainerURLs() {
            let cacheFile = containerURL
                .appendingPathComponent("Library/Caches")
                .appendingPathComponent("weatherCache.json")
            
            do {
                try fileManager.removeItem(at: cacheFile)
                logger.notice("✅ Cleared cache at: \(cacheFile.path)")
            } catch {
                logger.notice("ℹ️ No cache to clear at: \(cacheFile.path)")
            }
        }
        
        // Clear the container cache
        cachedContainers = nil
    }
    
    private func refreshWeatherData() async {
        logger.notice("🌤️ Starting weather data refresh...")
        do {
            if try await loadWeatherData() != nil {
                WidgetCenter.shared.reloadAllTimelines()
                logger.notice("✅ Refreshed data")
            }
        } catch {
            logger.error("❌ Failed to refresh weather data: \(error.localizedDescription)")
        }
    }
}