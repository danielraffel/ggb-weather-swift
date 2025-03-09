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
    private let maxCacheAge: TimeInterval = 24 * 60 * 60 // 24 hours instead of 15 minutes
    private let appGroupIdentifier = "group.genco"
    private let sharedDefaults: UserDefaults?
    private var cachedContainers: [URL]?
    
    public init() {
        self.sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
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
        
        // First, try to save to the specific container we know works
        let knownContainerUUID = "29054354-0907-4329-9C6A-84716EB850D4"
        let directContainerPath = "/private/var/mobile/Containers/Shared/AppGroup/\(knownContainerUUID)"
        
        if FileManager.default.fileExists(atPath: directContainerPath) {
            logger.notice("🎯 Directly targeting known container: \(knownContainerUUID)")
            
            // Save to both Preferences and Caches directories
            let prefsDir = URL(fileURLWithPath: "\(directContainerPath)/Library/Preferences")
            let cachesDir = URL(fileURLWithPath: "\(directContainerPath)/Library/Caches")
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
                    logger.error("❌ Failed to save to direct path at \(savePath.path): \(error)")
                }
            }
        }
        
        // Then try the standard approach with all containers
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
        
        // Also save to UserDefaults for redundancy
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(encodedData, forKey: "weatherData")
            sharedDefaults.set(encodedData, forKey: "cachedWeatherData")
            sharedDefaults.synchronize()
            logger.notice("✅ Saved to UserDefaults")
        }
        
        // Trigger widget refresh when new data is saved
        logger.notice("🔄 Triggering widget refresh")
        WidgetCenter.shared.reloadAllTimelines()
        
        // Add a delay and refresh again to ensure widget picks up the changes
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        WidgetCenter.shared.reloadAllTimelines()
        logger.notice("🔄 Triggered second widget refresh after 0.5s delay")
        
        // Add a third refresh after a longer delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        WidgetCenter.shared.reloadAllTimelines()
        logger.notice("🔄 Triggered third widget refresh after 1.5s total delay")
        
        // Add a fourth refresh after an even longer delay
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        WidgetCenter.shared.reloadAllTimelines()
        logger.notice("🔄 Triggered fourth widget refresh after 3.5s total delay")
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
        
        var newestCachedData: CachedWeatherData? = nil
        var newestCachedDataPath: String? = nil
        var newestTimestamp: Date? = nil
        
        // First try the known container directly
        let knownContainerUUID = "29054354-0907-4329-9C6A-84716EB850D4"
        let directContainerPath = "/private/var/mobile/Containers/Shared/AppGroup/\(knownContainerUUID)"
        
        if fileManager.fileExists(atPath: directContainerPath) {
            logger.notice("🎯 Directly checking known container for cache: \(knownContainerUUID)")
            
            let prefsPath = "\(directContainerPath)/Library/Preferences/weatherCache.json"
            let cachesPath = "\(directContainerPath)/Library/Caches/weatherCache.json"
            
            for path in [prefsPath, cachesPath] {
                if fileManager.fileExists(atPath: path),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let cachedData = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                    
                    let age = Date().timeIntervalSince(cachedData.timestamp)
                    logger.notice("📊 Found cache at \(path), age: \(Int(age)) seconds")
                    
                    // Check if this is newer than what we've found so far
                    if newestTimestamp == nil || cachedData.timestamp > newestTimestamp! {
                        newestCachedData = cachedData
                        newestCachedDataPath = path
                        newestTimestamp = cachedData.timestamp
                        logger.notice("⏱️ This is the newest cache so far")
                    }
                    
                    // If it's fresh enough, return it immediately
                    if age <= maxCacheAge {
                        logger.notice("✅ Found valid fresh cache at: \(path)")
                        return cachedData
                    }
                }
            }
        }
        
        // Then check all containers
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
                    logger.notice("📊 Found cache at \(cacheFile.path), age: \(Int(age)) seconds")
                    
                    // Check if this is newer than what we've found so far
                    if newestTimestamp == nil || cachedData.timestamp > newestTimestamp! {
                        newestCachedData = cachedData
                        newestCachedDataPath = cacheFile.path
                        newestTimestamp = cachedData.timestamp
                        logger.notice("⏱️ This is the newest cache so far")
                    }
                    
                    // If it's fresh enough, return it immediately
                    if age <= maxCacheAge {
                        logger.notice("✅ Found valid fresh cache at: \(cacheFile.path)")
                        return cachedData
                    } else {
                        logger.notice("⚠️ Cache expired at: \(cacheFile.path)")
                    }
                }
            }
        }
        
        // If we didn't find any fresh cache but found an expired one, use the newest expired cache
        if let cachedData = newestCachedData, let path = newestCachedDataPath {
            let age = Date().timeIntervalSince(cachedData.timestamp)
            logger.notice("⚠️ Using expired cache from \(path) (age: \(Int(age)) seconds) as no fresh cache was found")
            return cachedData
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
                    
                    logger.notice("🔍 Simulator root: \(simulatorRoot.path)")
                    
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