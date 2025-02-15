import WidgetKit
import SwiftUI
import Foundation
import os
import AppIntents

struct WeatherWidgetEntry: TimelineEntry {
    let date: Date
    let weatherData: WeatherData?
    let error: String?
    let bridgeImage: Data?
}

struct WeatherWidgetTimelineProvider: TimelineProvider {
    typealias Entry = WeatherWidgetEntry
    
    private let dataInteractor: SharedDataInteractorProtocol
    private static let logger = Logger(subsystem: "generouscorp.ggb", category: "WidgetTimelineProvider")
    private static let appGroupIdentifiers = ["group.genco", "group.generouscorp.ggb"]
    
    init(dataInteractor: SharedDataInteractorProtocol = SharedDataInteractor()) {
        self.dataInteractor = dataInteractor
        
        Self.logger.notice("⌚️ Widget Timeline Provider initializing...")
        
        // Debug app group access
        let fileManager = FileManager.default
        var allContainers: [URL] = []
        
        // First, try the standard app group identifiers
        for identifier in Self.appGroupIdentifiers {
            if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                allContainers.append(containerURL)
                Self.logger.notice("📂 Found container for \(identifier): \(containerURL.path)")
            }
        }
        
        // In simulator, we need to look in parent directories for other containers
        #if targetEnvironment(simulator)
        if let firstContainer = allContainers.first {
            Self.logger.notice("🔍 Running in simulator, searching for additional containers...")
            
            // Get simulator root directory (6 levels up from container)
            let simulatorRoot = firstContainer.deletingLastPathComponent() // AppGroup
                .deletingLastPathComponent() // Shared
                .deletingLastPathComponent() // Containers
                .deletingLastPathComponent() // data
                .deletingLastPathComponent() // DeviceID
                .deletingLastPathComponent() // Devices
            
            Self.logger.notice("📱 Simulator root: \(simulatorRoot.path)")
            
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
                                allContainers.append(group)
                                Self.logger.notice("✅ Found additional container in simulator: \(group.path)")
                            }
                        }
                    }
                }
            }
        }
        #endif
        
        Self.logger.notice("📂 Found \(allContainers.count) potential app group containers")
        
        // Check each container for valid data
        for container in allContainers {
            Self.logger.notice("   📂 Checking container: \(container.path)")
            
            // Check for existing cache files
            let prefsPath = container.appendingPathComponent("Library/Preferences/weatherCache.json")
            let cachesPath = container.appendingPathComponent("Library/Caches/weatherCache.json")
            
            // Check Preferences cache
            if fileManager.fileExists(atPath: prefsPath.path) {
                if let data = try? Data(contentsOf: prefsPath),
                   let cachedData = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                    Self.logger.notice("✅ Found valid cache file in Preferences (\(data.count) bytes)")
                    Self.logger.notice("📊 Cache contains \(cachedData.weatherData.count) weather items")
                    if let firstWeather = cachedData.weatherData.first {
                        Self.logger.notice("🌡️ First weather entry: \(firstWeather.temperature)°, \(firstWeather.windSpeed)mph")
                    }
                } else {
                    Self.logger.error("❌ Cache file in Preferences exists but cannot be read or decoded")
                }
            } else {
                Self.logger.error("❌ No cache file in Preferences")
            }
            
            // Check Caches cache
            if fileManager.fileExists(atPath: cachesPath.path) {
                if let data = try? Data(contentsOf: cachesPath),
                   let cachedData = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                    Self.logger.notice("✅ Found valid cache file in Caches (\(data.count) bytes)")
                    Self.logger.notice("📊 Cache contains \(cachedData.weatherData.count) weather items")
                    if let firstWeather = cachedData.weatherData.first {
                        Self.logger.notice("🌡️ First weather entry: \(firstWeather.temperature)°, \(firstWeather.windSpeed)mph")
                    }
                } else {
                    Self.logger.error("❌ Cache file in Caches exists but cannot be read or decoded")
                }
            } else {
                Self.logger.error("❌ No cache file in Caches")
            }
            
            // List directory contents
            let prefsDir = container.appendingPathComponent("Library/Preferences")
            let cachesDir = container.appendingPathComponent("Library/Caches")
            
            if let prefsContents = try? fileManager.contentsOfDirectory(at: prefsDir, includingPropertiesForKeys: nil) {
                Self.logger.notice("📂 Preferences directory contents: \(prefsContents.map { $0.lastPathComponent })")
            }
            
            if let cachesContents = try? fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil) {
                Self.logger.notice("📂 Caches directory contents: \(cachesContents.map { $0.lastPathComponent })")
            }
        }
        
        if allContainers.isEmpty {
            Self.logger.error("❌ Could not access any app group containers")
        }
    }
    
    func placeholder(in context: Context) -> WeatherWidgetEntry {
        Self.logger.notice("📍 Providing widget placeholder entry")
        let entry = WeatherWidgetEntry(date: Date(), weatherData: nil, error: "Loading...", bridgeImage: nil)
        Self.logger.notice("📍 Created placeholder entry with error: \(entry.error ?? "none")")
        return entry
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        Self.logger.notice("📸 Getting widget snapshot...")
        Task {
            do {
                let cachedData = try await dataInteractor.loadWeatherData(maxRetries: 3, retryDelay: 2.0)
                Self.logger.notice("📸 Widget snapshot data loaded: \(cachedData?.weatherData.count ?? 0) items")
                
                if let weatherData = cachedData?.weatherData.first {
                    Self.logger.notice("🌡️ Widget snapshot weather: \(weatherData.temperature)°, \(weatherData.windSpeed)mph")
                    let entry = WeatherWidgetEntry(
                        date: Date(),
                        weatherData: weatherData,
                        error: nil,
                        bridgeImage: cachedData?.bridgeImage
                    )
                    Self.logger.notice("✅ Widget snapshot created with weather data and \(cachedData?.bridgeImage != nil ? "bridge image (\(cachedData?.bridgeImage?.count ?? 0) bytes)" : "no bridge image")")
                    completion(entry)
                } else {
                    Self.logger.error("❌ No weather data available for widget snapshot")
                    let entry = WeatherWidgetEntry(
                        date: Date(),
                        weatherData: nil,
                        error: "No weather data available",
                        bridgeImage: nil
                    )
                    Self.logger.notice("⚠️ Created error entry: \(entry.error ?? "none")")
                    completion(entry)
                }
            } catch {
                Self.logger.error("❌ Widget snapshot error: \(error.localizedDescription)")
                let entry = WeatherWidgetEntry(
                    date: Date(),
                    weatherData: nil,
                    error: error.localizedDescription,
                    bridgeImage: nil
                )
                Self.logger.notice("⚠️ Created error entry: \(entry.error ?? "none")")
                completion(entry)
            }
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Self.logger.notice("🕒 Getting widget timeline...")
        Task {
            do {
                let cachedData = try await dataInteractor.loadWeatherData(maxRetries: 3, retryDelay: 2.0)
                Self.logger.notice("✅ Widget timeline data loaded. Items: \(cachedData?.weatherData.count ?? 0)")
                
                if let weatherData = cachedData?.weatherData, !weatherData.isEmpty {
                    let currentDate = Date()
                    let entries = weatherData
                        .filter { $0.time > currentDate }
                        .prefix(12)
                        .map { data in
                            Self.logger.notice("📊 Widget entry: \(data.time), temp: \(data.temperature)°")
                            return WeatherWidgetEntry(
                                date: data.time,
                                weatherData: data,
                                error: nil,
                                bridgeImage: cachedData?.bridgeImage
                            )
                        }
                    
                    if entries.isEmpty {
                        Self.logger.notice("⚠️ No future entries, using current data")
                        let entry = WeatherWidgetEntry(
                            date: currentDate,
                            weatherData: weatherData.first,
                            error: nil,
                            bridgeImage: cachedData?.bridgeImage
                        )
                        if let weather = weatherData.first {
                            Self.logger.notice("🌡️ Widget using current: \(weather.temperature)°, \(weather.windSpeed)mph, bridge image: \(cachedData?.bridgeImage != nil)")
                        }
                        Self.logger.notice("✅ Created single entry timeline")
                        completion(Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(30))))
                        return
                    }
                    
                    Self.logger.notice("✅ Widget timeline: \(entries.count) entries, \(cachedData?.bridgeImage != nil ? "with bridge image (\(cachedData?.bridgeImage?.count ?? 0) bytes)" : "without bridge image")")
                    completion(Timeline(entries: Array(entries), policy: .after(currentDate.addingTimeInterval(60))))
                } else {
                    Self.logger.error("❌ No weather data for widget timeline")
                    let entry = WeatherWidgetEntry(
                        date: .now,
                        weatherData: nil,
                        error: "No weather data available",
                        bridgeImage: nil
                    )
                    Self.logger.notice("⚠️ Created error timeline entry: \(entry.error ?? "none")")
                    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30))))
                }
            } catch {
                Self.logger.error("❌ Widget timeline error: \(error.localizedDescription)")
                let entry = WeatherWidgetEntry(
                    date: .now,
                    weatherData: nil,
                    error: error.localizedDescription,
                    bridgeImage: nil
                )
                Self.logger.notice("⚠️ Created error timeline entry: \(entry.error ?? "none")")
                completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30))))
            }
        }
    }
} 