import Foundation
import os
import WatchConnectivity
import WidgetKit

@globalActor
public actor SharedDataActor {
    public static let shared = SharedDataActor()
}

public final class SharedDataInteractor: SharedDataInteractorProtocol {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "SharedDataInteractor")
    private let maxCacheAge: TimeInterval = 15 * 60 // 15 minutes
    private let appGroupIdentifier = "group.genco"
    private let sharedDefaults: UserDefaults?
    private var session: WCSession?
    
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
        logger.notice("🔧 Initializing SharedDataInteractor...")
        
        // Initialize WatchConnectivity first
        logger.notice("⌚️ Setting up WatchConnectivity...")
        if WCSession.isSupported() {
            logger.notice("✅ WatchConnectivity is supported")
            session = WCSession.default
            session?.delegate = self
            logger.notice("✅ WCSession delegate set")
            session?.activate()
            logger.notice("✅ WCSession activation requested")
            
            if let session = session {
                logger.notice("⌚️ Initial WCSession state:")
                logger.notice("   - Session: \(session)")
                logger.notice("   - Paired: \(session.isPaired)")
                logger.notice("   - Watch App Installed: \(session.isWatchAppInstalled)")
                logger.notice("   - Reachable: \(session.isReachable)")
                logger.notice("   - Activation State: \(session.activationState.rawValue)")
                
                if ProcessInfo.processInfo.isWatchOS {
                    logger.notice("⌚️ Running on watchOS, will request data from iOS app")
                    Task {
                        logger.notice("⌚️ Sending initial data request to iOS app...")
                        do {
                            let message: [String: Any] = ["request": "weatherData"]
                            logger.notice("📤 Sending message: \(message)")
                            let reply = try await session.sendMessage(message, replyHandler: { reply in
                                logger.notice("📥 Got immediate reply: \(reply)")
                                return reply
                            })
                            logger.notice("✅ Got reply with keys: \(reply.keys.joined(separator: ", "))")
                        } catch {
                            logger.error("❌ Failed initial data request: \(error.localizedDescription)")
                        }
                    }
                } else {
                    logger.notice("📱 Running on iOS, ready to respond to watch requests")
                }
            }
        } else {
            logger.error("❌ WatchConnectivity not supported")
        }
        
        // Initialize shared UserDefaults
        self.sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        
        // Debug app group access
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
                    let encoder = JSONEncoder()
                    let encodedData = try encoder.encode(data)
                    try encodedData.write(to: savePath, options: .atomic)
                    
                    if let size = try? savePath.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        logger.notice("✅ Successfully saved weather data to \(savePath.path). Items: \(data.weatherData.count), Size: \(size) bytes")
                    }
                } catch {
                    logger.error("❌ Failed to save to cache at \(savePath.path): \(error)")
                }
            }
        }
        
        // Send to watch if available
        if let session = session, session.isPaired && session.isReachable {
            do {
                let encoder = JSONEncoder()
                let encodedData = try encoder.encode(data)
                try await session.sendMessageData(encodedData)
                logger.notice("✅ Sent weather data to watch")
            } catch {
                logger.error("❌ Failed to send data to watch: \(error.localizedDescription)")
            }
        }
    }
    
    @SharedDataActor
    public func loadWeatherData(maxRetries: Int = 3, retryDelay: TimeInterval = 2.0) async throws -> CachedWeatherData? {
        // For watchOS, try WatchConnectivity first
        if ProcessInfo.processInfo.isWatchOS {
            logger.notice("⌚️ Running on watchOS, checking WatchConnectivity...")
            if let session = session {
                logger.notice("📱 WCSession Status:")
                logger.notice("   - Paired: \(session.isPaired)")
                logger.notice("   - Watch App Installed: \(session.isWatchAppInstalled)")
                logger.notice("   - Reachable: \(session.isReachable)")
                logger.notice("   - Activation State: \(session.activationState.rawValue)")
                
                // Always try to request data, regardless of reachability
                for attempt in 1...maxRetries {
                    logger.notice("⌚️ Attempting to request data from iOS app (attempt \(attempt)/\(maxRetries))...")
                    do {
                        let message: [String: Any] = ["request": "weatherData"]
                        let reply = try await session.sendMessage(message)
                        logger.notice("✅ Received reply from iOS app on attempt \(attempt)")
                        
                        if let encodedData = reply["weatherData"] as? Data {
                            let decoder = JSONDecoder()
                            let data = try decoder.decode(CachedWeatherData.self, from: encodedData)
                            logger.notice("✅ Successfully decoded weather data from iOS app")
                            return data
                        } else {
                            logger.error("❌ No weather data in reply from iOS app (attempt \(attempt))")
                        }
                    } catch {
                        logger.error("❌ Failed to request data from iOS app (attempt \(attempt)): \(error.localizedDescription)")
                    }
                    
                    if attempt < maxRetries {
                        logger.notice("⏳ Waiting \(retryDelay) seconds before next attempt...")
                        try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                    }
                }
            } else {
                logger.error("❌ WCSession not initialized")
            }
        }
        
        // Fallback to app group
        if let data = try? await loadFromUserDefaults() ?? await loadFromFileCache() {
            logger.notice("✅ Found data in app group")
            return data
        }
        
        logger.error("❌ No data found in shared cache or from iOS app")
        throw SharedDataError.cacheEmpty
    }
    
    private func loadFromUserDefaults() async throws -> CachedWeatherData? {
        logger.notice("�� Attempting to load from UserDefaults with group: \(appGroupIdentifier)")
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            logger.error("❌ Could not access shared UserDefaults")
            return nil
        }
        if let encodedData = sharedDefaults.data(forKey: "cachedWeatherData") {
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
        var containers: [URL] = []
        
        if let mainContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            containers.append(mainContainer)
            
            // Get simulator root directory
            if mainContainer.path.contains("CoreSimulator") {
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
                                // Check if this is our app group by looking for our cache file
                                let prefsPath = group.appendingPathComponent("Library/Preferences/weatherCache.json")
                                let cachesPath = group.appendingPathComponent("Library/Caches/weatherCache.json")
                                
                                if fileManager.fileExists(atPath: prefsPath.path) || fileManager.fileExists(atPath: cachesPath.path) {
                                    containers.append(group)
                                    logger.notice("✅ Found existing cache in simulator device: \(deviceDir.lastPathComponent)")
                                }
                            }
                        }
                    }
                }
            }
        } else {
            logger.error("❌ Could not access app group container for identifier: \(appGroupIdentifier)")
        }
        
        logger.notice("📱 Found \(containers.count) potential app group containers")
        containers.forEach { logger.notice("   📂 \($0.path)") }
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
    }
}

extension SharedDataInteractor: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("❌ WCSession activation failed: \(error.localizedDescription)")
            return
        }
        logger.notice("✅ WCSession activated with state: \(activationState.rawValue)")
        
        // For iOS app, send initial data if available
        if !ProcessInfo.processInfo.isWatchOS {
            Task {
                if let data = try? await loadWeatherData() {
                    try? await session.sendMessageData(JSONEncoder().encode(data), replyHandler: nil)
                    logger.notice("✅ Sent initial data to watch")
                }
            }
        }
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        logger.notice("📥 Received message: \(message)")
        
        Task {
            if let request = message["request"] as? String {
                switch request {
                case "weatherData":
                    if let data = try? await loadWeatherData() {
                        // Split data: weather data via transferUserInfo, image via transferFile
                        let encoder = JSONEncoder()
                        var weatherDataOnly = data
                        let imageData = data.bridgeImage
                        weatherDataOnly.bridgeImage = nil
                        
                        if let encodedWeatherData = try? encoder.encode(weatherDataOnly) {
                            // Send weather data via transferUserInfo
                            session.transferUserInfo(["weatherData": encodedWeatherData])
                            logger.notice("✅ Sent weather data via transferUserInfo")
                            
                            // Send image via transferFile if available
                            if let imageData = imageData {
                                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("bridgeImage.jpg")
                                try? imageData.write(to: tempURL)
                                session.transferFile(tempURL, metadata: ["type": "bridgeImage"])
                                logger.notice("✅ Sent bridge image via transferFile")
                            }
                            
                            // Send immediate small response
                            replyHandler(["status": "transferStarted"])
                        } else {
                            replyHandler(["error": "Failed to encode weather data"])
                            logger.error("❌ Failed to encode weather data")
                        }
                    } else {
                        replyHandler(["error": "No weather data available"])
                        logger.error("❌ No weather data available")
                    }
                    
                default:
                    replyHandler(["error": "Unknown request"])
                    logger.error("❌ Unknown request type: \(request)")
                }
            } else {
                replyHandler(["error": "Invalid request"])
                logger.error("❌ No request type in message")
            }
        }
    }
    
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        logger.notice("📥 Received file transfer")
        if file.metadata?["type"] as? String == "bridgeImage" {
            Task {
                if var data = try? await loadWeatherData() {
                    data.bridgeImage = try? Data(contentsOf: file.fileURL)
                    try? await saveWeatherData(data)
                    logger.notice("✅ Saved received bridge image")
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
    
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        logger.notice("📥 Received user info transfer")
        if let weatherData = userInfo["weatherData"] as? Data {
            Task {
                do {
                    var data = try JSONDecoder().decode(CachedWeatherData.self, from: weatherData)
                    // Keep existing image if available
                    if let existingData = try? await loadWeatherData() {
                        data.bridgeImage = existingData.bridgeImage
                    }
                    try await saveWeatherData(data)
                    logger.notice("✅ Saved received weather data")
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    logger.error("❌ Failed to process received weather data: \(error)")
                }
            }
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
}

private extension ProcessInfo {
    var isWatchOS: Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }
    
    var isiOSAppOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }
}

private extension Data {
    func chunked(into size: Int) -> [Data] {
        stride(from: 0, to: count, by: size).map {
            let end = Swift.min($0 + size, count)
            return self[$0..<end]
        }
    }
}

struct CachedWeatherData: Codable {
    var weatherData: [WeatherData]
    var bridgeImage: Data?
    var lastUpdated: Date
    
    init(weatherData: [WeatherData], bridgeImage: Data? = nil, lastUpdated: Date = Date()) {
        self.weatherData = weatherData
        self.bridgeImage = bridgeImage
        self.lastUpdated = lastUpdated
    }
} 