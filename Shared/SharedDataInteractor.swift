import Foundation
import os

public final class SharedDataInteractor: SharedDataInteractorProtocol {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "generouscorp.SS2.ggbweather", category: "SharedDataInteractor", log: .default)
    private let maxCacheAge: TimeInterval = 15 * 60 // 15 minutes
    private let appGroupIdentifier = "group.generouscorp.SS2.ggbweather"
    private let sharedDefaults: UserDefaults?
    
    private func dumpAppGroupInfo() {
        let isWatchApp = ProcessInfo.processInfo.isiOSAppOnMac ? "📱 iOS" : "⌚️ watchOS"
        logger.notice("\(isWatchApp) Process: \(ProcessInfo.processInfo.processName)")
        
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let permissions = try? fileManager.attributesOfItem(atPath: containerURL.path)[.posixPermissions] as? Int
            logger.notice("📂 Container permissions: \(permissions ?? 0)")
            
            let testFile = containerURL.appendingPathComponent("test.txt")
            do {
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                try fileManager.removeItem(at: testFile)
                logger.notice("✅ Container write test successful")
            } catch {
                logger.error("❌ Container write test failed: \(error.localizedDescription)")
            }
        }
        
        logger.notice("📊 App Group Debug Info:")
        logger.notice("🆔 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        
        // Check UserDefaults
        if let sharedDefaults = sharedDefaults {
            logger.notice("💾 UserDefaults initialized")
            if let data = sharedDefaults.data(forKey: "cachedWeatherData") {
                logger.notice("📦 UserDefaults has data: \(data.count) bytes")
            } else {
                logger.notice("⚠️ No data in UserDefaults")
            }
        }
        
        // Check container
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            logger.notice("📂 Container: \(containerURL.path)")
            let prefsURL = containerURL.appendingPathComponent("Library/Preferences")
            let cacheFile = prefsURL.appendingPathComponent("weatherCache.json")
            
            if fileManager.fileExists(atPath: cacheFile.path) {
                if let attrs = try? fileManager.attributesOfItem(atPath: cacheFile.path) {
                    logger.notice("📄 Cache file exists: \(attrs[.size] ?? 0) bytes")
                    logger.notice("⏰ Modified: \(attrs[.modificationDate] ?? Date())")
                }
            } else {
                logger.notice("⚠️ No cache file found")
            }
        }
    }
    
    public init() {
        // Initialize shared UserDefaults
        self.sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        
        logger.notice("🔧 Initializing SharedDataInteractor...")
        dumpAppGroupInfo()
        logger.notice("📱 Process: \(ProcessInfo.processInfo.processName) (PID: \(ProcessInfo.processInfo.processIdentifier))")
        logger.notice("🔑 App Group ID: \(appGroupIdentifier)")
        logger.notice("💾 Shared UserDefaults: \(sharedDefaults != nil ? "initialized" : "failed")")
        
        // Debug app group access
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            logger.notice("📂 App group container path: \(containerURL.path)")
            
            // List all app group containers
            if let appGroupsURL = containerURL.deletingLastPathComponent().deletingLastPathComponent() as URL? {
                do {
                    let contents = try fileManager.contentsOfDirectory(at: appGroupsURL, includingPropertiesForKeys: nil)
                    logger.notice("📑 All app group containers: \(contents.map { $0.lastPathComponent })")
                } catch {
                    logger.error("❌ Failed to list app group containers: \(error.localizedDescription)")
                }
            }
            
            // Create Preferences directory if it doesn't exist
            let prefsURL = containerURL.appendingPathComponent("Library/Preferences")
            do {
                try fileManager.createDirectory(at: prefsURL, withIntermediateDirectories: true)
                logger.notice("✅ Preferences directory ensured at: \(prefsURL.path)")
                
                // List contents of preferences directory
                let contents = try fileManager.contentsOfDirectory(at: prefsURL, includingPropertiesForKeys: [.fileSizeKey])
                logger.notice("📑 Preferences directory contents:")
                for file in contents {
                    let attrs = try file.resourceValues(forKeys: [.fileSizeKey])
                    logger.notice("   - \(file.lastPathComponent) (size: \(attrs.fileSize ?? 0) bytes)")
                }
            } catch {
                logger.error("❌ Failed to create preferences directory: \(error.localizedDescription)")
            }
        } else {
            logger.error("❌ Could not access app group container for identifier: \(appGroupIdentifier)")
        }
        
        logger.notice("✅ SharedDataInteractor initialized successfully")
    }
    
    @SharedDataActor
    public func saveWeatherData(_ data: CachedWeatherData) async throws {
        logger.notice("💾 Attempting to save weather data...")
        
        for containerURL in getContainerURLs() {
            let prefsDir = containerURL.appendingPathComponent("Library/Preferences")
            let cacheFile = prefsDir.appendingPathComponent("weatherCache.json")
            
            do {
                try fileManager.createDirectory(at: prefsDir, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                let encodedData = try encoder.encode(data)
                try encodedData.write(to: cacheFile, options: .atomic)
                
                if let size = try? cacheFile.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    logger.notice("✅ Successfully saved weather data. Items: \(data.hourlyForecasts.count), Size: \(size) bytes")
                }
            } catch {
                logger.error("❌ Failed to save to cache at \(cacheFile.path): \(error)")
            }
        }
    }
    
    @SharedDataActor
    public func loadWeatherData(maxRetries: Int = 3, retryDelay: TimeInterval = 2.0) async throws -> CachedWeatherData? {
        logger.notice("📂 Attempting to load weather data... (Attempt 1/\(maxRetries))")
        
        for attempt in 1...maxRetries {
            // Try UserDefaults first
            if let data = try? await loadFromUserDefaults() {
                return data
            }
            
            // Try file cache
            if let data = try? await loadFromFileCache() {
                return data
            }
            
            if attempt < maxRetries {
                logger.notice("⏳ Retry \(attempt)/\(maxRetries) - Waiting \(retryDelay)s before next attempt")
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        
        logger.error("❌ No data found after \(maxRetries) attempts")
        throw SharedDataError.cacheEmpty
    }
    
    private func loadFromUserDefaults() async throws -> CachedWeatherData? {
        if let sharedDefaults = sharedDefaults,
           let encodedData = sharedDefaults.data(forKey: "cachedWeatherData") {
            let decoder = JSONDecoder()
            let cachedData = try decoder.decode(CachedWeatherData.self, from: encodedData)
            let age = Date().timeIntervalSince(cachedData.timestamp)
            
            if age <= maxCacheAge {
                logger.notice("✅ Loaded from UserDefaults. Age: \(Int(age))s")
                return cachedData
            }
        }
        return nil
    }
    
    private func getContainerURLs() -> [URL] {
        var containers: [URL] = []
        
        if let mainContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            containers.append(mainContainer)
            
            if mainContainer.path.contains("CoreSimulator") {
                // Get simulator root directory
                let simulatorRoot = mainContainer.deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                
                // Look for app group containers in all simulator devices
                if let deviceDirs = try? fileManager.contentsOfDirectory(at: simulatorRoot.appendingPathComponent("Devices"), includingPropertiesForKeys: nil) {
                    for deviceDir in deviceDirs where deviceDir.hasDirectoryPath {
                        let appGroupPath = deviceDir.appendingPathComponent("data/Containers/Shared/AppGroup")
                        if let appGroups = try? fileManager.contentsOfDirectory(at: appGroupPath, includingPropertiesForKeys: nil) {
                            for group in appGroups where group.hasDirectoryPath {
                                let metadataURL = group.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                                if let data = try? Data(contentsOf: metadataURL),
                                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                                   let mcmMetadata = plist["MCMMetadataIdentifier"] as? String,
                                   mcmMetadata.contains(appGroupIdentifier) {
                                    containers.append(group)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        logger.notice("📱 Found \(containers.count) potential app group containers")
        containers.forEach { logger.notice("   📂 \($0.path)") }
        return containers
    }
    
    private func loadFromFileCache() async throws -> CachedWeatherData? {
        logger.notice("📂 Attempting to load weather data...")
        
        for containerURL in getContainerURLs() {
            let cacheFile = containerURL
                .appendingPathComponent("Library/Caches")
                .appendingPathComponent("weatherCache.json")
                
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
        
        logger.error("❌ No data found in shared cache")
        return nil
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
    }
} 