//
//  GGB_Watch_Widget_Extension.swift
//  GGB Watch Widget Extension
//
//  Created by Daniel Raffel on 2/1/25.
//

import WidgetKit
import SwiftUI
import Foundation
import WatchKit
import AppIntents
import os
// import Shared

private let logger = Logger(subsystem: "generouscorp.ggb", category: "WatchWidget")

// MARK: - Extensions
extension DateFormatter {
    static func with(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Data Models
struct WeatherWidgetEntry: TimelineEntry {
    let date: Date
    let weatherData: WeatherData?
    let error: String?
    let bridgeImage: Data?
    
    struct WeatherData {
        let time: Date
        let temperature: Double
        let cloudCover: Double
        let windSpeed: Double
        let precipitationProbability: Double
    }
}

// MARK: - Timeline Provider
class WeatherWidgetTimelineProvider: TimelineProvider {
    typealias Entry = WeatherWidgetEntry
    
    func placeholder(in context: Context) -> Entry {
        WeatherWidgetEntry(
            date: Date(),
            weatherData: nil as WeatherWidgetEntry.WeatherData?,
            error: "Loading...",
            bridgeImage: nil as Data?
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        // Use the same data loading logic as getTimeline for consistency
        logger.notice("📸 Getting widget snapshot...")
        
        // Try to load real data first
        loadWeatherData { entry in
            if entry.weatherData != nil {
                logger.notice("✅ Snapshot using real data")
                completion(entry)
            } else {
                // Fall back to placeholder only if real data can't be loaded
                logger.notice("⚠️ Snapshot using placeholder data")
                let placeholderEntry = WeatherWidgetEntry(
                    date: Date(),
                    weatherData: WeatherWidgetEntry.WeatherData(
                        time: Date(),
                        temperature: 68,
                        cloudCover: 25,
                        windSpeed: 12,
                        precipitationProbability: 15
                    ),
                    error: nil as String?,
                    bridgeImage: nil as Data?
                )
                completion(placeholderEntry)
            }
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        logger.notice("🕒 Getting widget timeline...")
        
        // Log widget extension info for debugging
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        logger.notice("🏷️ Widget extension bundle ID: \(bundleID)")
        logger.notice("📃 Widget entitlements should include group.genco")
        
        // Print widget family and context for debugging
        #if os(iOS)
        if let family = context.family as? WidgetFamily {
            logger.notice("📱 Widget family requested: \(family)")
        }
        #elseif os(watchOS)
        if let family = context.family as? WidgetFamily {
            logger.notice("⌚️ Watch widget family requested: \(family)")
        }
        #endif
        
        logger.notice("📏 Widget size: \(context.displaySize.width) x \(context.displaySize.height)")
        
        // Check app group entitlements at runtime
        let entitlementTest = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.genco")
        if entitlementTest != nil {
            logger.notice("✅ App group entitlement check passed: \(entitlementTest!.path)")
        } else {
            logger.error("❌ App group entitlement check FAILED - widget cannot access group.genco")
        }
        
        loadWeatherData { entry in
            // Determine next refresh time based on data availability
            let refreshInterval: TimeInterval
            
            if entry.weatherData != nil {
                // If we have data, refresh in 5-15 minutes depending on visibility
                #if os(iOS)
                refreshInterval = context.isPreview ? 60 * 60 : (context.family == .systemSmall ? 5 * 60 : 15 * 60)
                #else
                refreshInterval = context.isPreview ? 60 * 60 : 15 * 60
                #endif
                logger.notice("⏱️ Setting refresh interval to \(Int(refreshInterval/60)) minutes")
            } else {
                // If no data, try again sooner
                refreshInterval = 5 * 60
                logger.notice("⏱️ No data found, will retry in 5 minutes")
            }
            
            // Create timeline with appropriate refresh policy
            let nextUpdate = Date().addingTimeInterval(refreshInterval)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    // Helper method to load weather data
    private func loadWeatherData(completion: @escaping (WeatherWidgetEntry) -> Void) {
        // First try to find the correct container
        func findAppGroupContainers() -> [URL] {
            var containers: [URL] = []
            let fileManager = FileManager.default
            let appGroupIdentifiers = ["group.genco", "group.generouscorp.ggb"]
            
            // Log environment
            #if targetEnvironment(simulator)
            logger.notice("🔍 Running on simulator")
            #else
            logger.notice("🔍 Running on physical device")
            #endif
            
            // APPROACH 1: Try standard app group container access
            for identifier in appGroupIdentifiers {
                if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                    containers.append(containerURL)
                    logger.notice("📂 [APPROACH 1] Found container for \(identifier): \(containerURL.path)")
                }
            }
            
            // APPROACH 2: For simulator only - Search for containers in simulator directory
            #if targetEnvironment(simulator)
            if let containerURL = containers.first {
                // Get simulator root directory (6 levels up from container)
                let simulatorRoot = containerURL.deletingLastPathComponent() // AppGroup
                    .deletingLastPathComponent() // Shared
                    .deletingLastPathComponent() // Containers
                    .deletingLastPathComponent() // data
                    .deletingLastPathComponent() // DeviceID
                    .deletingLastPathComponent() // Devices
            
                logger.notice("🔍 [APPROACH 2] Simulator root: \(simulatorRoot.path)")
            
                // Look for app group containers in all simulator devices
                if let deviceDirs = try? fileManager.contentsOfDirectory(at: simulatorRoot, includingPropertiesForKeys: nil) {
                    for deviceDir in deviceDirs where deviceDir.hasDirectoryPath {
                        let appGroupPath = deviceDir.appendingPathComponent("data/Containers/Shared/AppGroup")
                        if fileManager.fileExists(atPath: appGroupPath.path) {
                            if let appGroups = try? fileManager.contentsOfDirectory(at: appGroupPath, includingPropertiesForKeys: nil) {
                                for group in appGroups where group.hasDirectoryPath {
                                    // Check if this is our app group by looking for our cache file
                                    let prefsPath = group.appendingPathComponent("Library/Preferences/weatherCache.json")
                                    let cachesPath = group.appendingPathComponent("Library/Caches/weatherCache.json")
                                    
                                    if fileManager.fileExists(atPath: prefsPath.path) || fileManager.fileExists(atPath: cachesPath.path) {
                                        if !containers.contains(group) {
                                            containers.append(group)
                                            logger.notice("✅ [APPROACH 2] Found additional container in simulator: \(group.path)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            #endif
            
            // APPROACH 3: For physical devices (and simulator fallback)
            // Search all app group containers for our files
            let basePath = "/private/var/mobile/Containers/Shared/AppGroup"
            
            // Scan all available containers for our cache files
            if fileManager.fileExists(atPath: basePath) {
                do {
                    let contents = try fileManager.contentsOfDirectory(atPath: basePath)
                    logger.notice("🔍 [APPROACH 3] Found \(contents.count) potential UUID directories to check")
                    
                    for uuid in contents {
                        let containerPath = "\(basePath)/\(uuid)"
                        
                        // First check our standard cache locations
                        let prefsCachePath = "\(containerPath)/Library/Preferences/weatherCache.json"
                        let cachesCachePath = "\(containerPath)/Library/Caches/weatherCache.json"
                        
                        if fileManager.fileExists(atPath: prefsCachePath) || 
                           fileManager.fileExists(atPath: cachesCachePath) {
                            let containerURL = URL(fileURLWithPath: containerPath)
                            if !containers.contains(containerURL) {
                                containers.append(containerURL)
                                logger.notice("✅ [APPROACH 3] Found container with our cache files: \(containerPath)")
                            }
                            continue
                        }
                        
                        // If no cache files found directly, check if it might be our container by looking for preferences
                        let prefsDir = "\(containerPath)/Library/Preferences"
                        if fileManager.fileExists(atPath: prefsDir) {
                            do {
                                let prefsContents = try fileManager.contentsOfDirectory(atPath: prefsDir)
                                // Look for any plist file that might be related to our app
                                let appRelatedFiles = prefsContents.filter { 
                                    $0.contains("genco") || $0.contains("generouscorp") || $0.contains("ggb") 
                                }
                                
                                if !appRelatedFiles.isEmpty {
                                    let containerURL = URL(fileURLWithPath: containerPath)
                                    if !containers.contains(containerURL) {
                                        containers.append(containerURL)
                                        logger.notice("✅ [APPROACH 3] Found probable container with app preferences: \(containerPath)")
                                        logger.notice("   📄 Relevant files: \(appRelatedFiles.joined(separator: ", "))")
                                    }
                                }
                            } catch {
                                logger.error("❌ Error checking preferences directory: \(error.localizedDescription)")
                            }
                        }
                    }
                } catch {
                    logger.error("❌ Error listing app group containers: \(error.localizedDescription)")
                }
            } else {
                logger.error("❌ Base app group path does not exist or is not accessible")
            }
            
            // APPROACH 4: Last resort - scan all containers for any readable JSONs
            if containers.isEmpty {
                logger.notice("🔍 [APPROACH 4] No containers found yet, scanning all for any JSONs...")
                if fileManager.fileExists(atPath: basePath) {
                    do {
                        let contents = try fileManager.contentsOfDirectory(atPath: basePath)
                        
                        for uuid in contents {
                            let containerPath = "\(basePath)/\(uuid)"
                            let containerURL = URL(fileURLWithPath: containerPath)
                            
                            // Check common paths for any JSON files
                            let commonPaths = [
                                "\(containerPath)/Library/Preferences",
                                "\(containerPath)/Library/Caches"
                            ]
                            
                            for path in commonPaths {
                                if fileManager.fileExists(atPath: path) {
                                    do {
                                        let files = try fileManager.contentsOfDirectory(atPath: path)
                                        let jsonFiles = files.filter { $0.hasSuffix(".json") }
                                        
                                        if !jsonFiles.isEmpty && !containers.contains(containerURL) {
                                            containers.append(containerURL)
                                            logger.notice("✅ [APPROACH 4] Found container with JSON files: \(containerPath)")
                                            logger.notice("   📄 JSON files: \(jsonFiles.joined(separator: ", "))")
                                            break
                                        }
                                    } catch {
                                        logger.error("❌ Error checking directory for JSONs: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    } catch {
                        logger.error("❌ Error listing app group containers: \(error.localizedDescription)")
                    }
                }
            }
            
            // Make sure we have unique containers only
            let uniqueContainers = Array(Set(containers.map { $0.path })).map { URL(fileURLWithPath: $0) }
            
            // Validate each container by checking for specific files and validating JSON
            logger.notice("🔍 Found \(uniqueContainers.count) total potential app group containers to validate")
            var validatedContainers: [URL] = []
            
            for (index, container) in uniqueContainers.enumerated() {
                logger.notice("   📂 [\(index + 1)] Validating container: \(container.path)")
                var isValid = false
            
            // Check for existing cache files
            let prefsPath = container.appendingPathComponent("Library/Preferences/weatherCache.json")
            let cachesPath = container.appendingPathComponent("Library/Caches/weatherCache.json")
            
                // Try preferences path
            if fileManager.fileExists(atPath: prefsPath.path) {
                    logger.notice("      ✅ Found cache in Preferences")
                    do {
                        let data = try Data(contentsOf: prefsPath)
                        if let _ = try? JSONSerialization.jsonObject(with: data) {
                            logger.notice("      ✅ Valid JSON in Preferences")
                            isValid = true
                        } else {
                            logger.error("      ❌ Invalid JSON format in Preferences")
                        }
                    } catch {
                        logger.error("      ❌ Error reading Preferences cache: \(error.localizedDescription)")
                    }
                }
                
                // Try caches path
                if fileManager.fileExists(atPath: cachesPath.path) {
                    logger.notice("      ✅ Found cache in Caches")
                    do {
                        let data = try Data(contentsOf: cachesPath)
                        if let _ = try? JSONSerialization.jsonObject(with: data) {
                            logger.notice("      ✅ Valid JSON in Caches")
                            isValid = true
                } else {
                            logger.error("      ❌ Invalid JSON format in Caches")
                        }
                    } catch {
                        logger.error("      ❌ Error reading Caches cache: \(error.localizedDescription)")
                    }
                }
                
                if isValid {
                    validatedContainers.append(container)
                }
            }
            
            // Return validated containers first, then all containers if no valid ones were found
            return validatedContainers.isEmpty ? uniqueContainers : validatedContainers
        }
        
        // Find all potential containers
        let containers = findAppGroupContainers()
        var weatherData: Data? = nil
        var bridgeImageData: Data? = nil
        var dataSourcePath: String? = nil
        
        // Try to load data from each container
        for container in containers {
            logger.notice("📂 Trying to load data from container: \(container.path)")
            
            let paths = [
                container.appendingPathComponent("Library/Preferences/weatherCache.json"),
                container.appendingPathComponent("Library/Caches/weatherCache.json")
            ]
            
            for path in paths {
                if FileManager.default.fileExists(atPath: path.path) {
                    do {
                        let tempData = try Data(contentsOf: path)
                        // Verify this is valid JSON before accepting it
                        if let _ = try? JSONSerialization.jsonObject(with: tempData) {
                            weatherData = tempData
                            dataSourcePath = path.path
                            logger.notice("✅ Loaded valid JSON data from \(path.path): \(weatherData?.count ?? 0) bytes")
                            break
                        } else {
                            logger.error("⚠️ File exists but contains invalid JSON: \(path.path)")
                        }
                    } catch {
                        logger.error("❌ Error loading from \(path.path): \(error.localizedDescription)")
                    }
                } else {
                    logger.notice("⚠️ File doesn't exist: \(path.path)")
                }
            }
            
            // If we found data, also look for bridge image
            if weatherData != nil {
                let imagePath = container.appendingPathComponent("Library/Caches/bridgeImage.data")
                if FileManager.default.fileExists(atPath: imagePath.path) {
                    do {
                        bridgeImageData = try Data(contentsOf: imagePath)
                        logger.notice("✅ Loaded bridge image: \(bridgeImageData?.count ?? 0) bytes")
                    } catch {
                        logger.error("❌ Error loading bridge image: \(error.localizedDescription)")
                    }
                }
                break // Stop after finding valid data
            }
        }
        
        // Process the weather data if we found it
        if let data = weatherData, let json = try? JSONSerialization.jsonObject(with: data) {
            logger.notice("✅ Successfully parsed JSON data from \(dataSourcePath ?? "unknown location")")
            
            // Try different formats the data might be in
            var weatherItems: [[String: Any]]? = nil
            var firstItem: [String: Any]? = nil
            
            // Format 1: {"weatherData": [{...}, {...}]}
            if let jsonDict = json as? [String: Any],
               let items = jsonDict["weatherData"] as? [[String: Any]],
               !items.isEmpty {
                weatherItems = items
                firstItem = items.first
                logger.notice("📊 Found data in format 1 (weatherData array)")
            }
            
            // Format 2: Direct array of weather data [{...}, {...}]
            else if let items = json as? [[String: Any]], !items.isEmpty {
                weatherItems = items
                firstItem = items.first
                logger.notice("📊 Found data in format 2 (direct array)")
            }
            
            // Format 3: Single weather item {...}
            else if let item = json as? [String: Any] {
                weatherItems = [item]
                firstItem = item
                logger.notice("📊 Found data in format 3 (single item)")
            }
            
            // Now process the first item if we found one
            if let current = firstItem {
                // Log the keys we found to help with debugging
                logger.notice("📋 Found keys: \(current.keys.joined(separator: ", "))")
                
                // Try to extract values with fallbacks
                var temperatureValue: Double = 0
                if let temp = current["temperature"] as? Double {
                    temperatureValue = temp
                } else if let temp = current["temperature"] as? Int {
                    temperatureValue = Double(temp)
                } else if let temp = current["temp"] as? Double {
                    temperatureValue = temp
                } else if let temp = current["temp"] as? Int {
                    temperatureValue = Double(temp)
                }
                
                var cloudCover: Double = 0
                if let cloud = current["cloudCover"] as? Double {
                    cloudCover = cloud
                } else if let cloud = current["cloudCover"] as? Int {
                    cloudCover = Double(cloud)
                } else if let cloud = current["clouds"] as? Double {
                    cloudCover = cloud
                } else if let cloud = current["clouds"] as? Int {
                    cloudCover = Double(cloud)
                }
                
                var windSpeed: Double = 0
                if let wind = current["windSpeed"] as? Double {
                    windSpeed = wind
                } else if let wind = current["windSpeed"] as? Int {
                    windSpeed = Double(wind)
                } else if let wind = current["wind"] as? Double {
                    windSpeed = wind
                } else if let wind = current["wind"] as? Int {
                    windSpeed = Double(wind)
                }
                
                var precipProb: Double = 0
                if let precip = current["precipitationProbability"] as? Double {
                    precipProb = precip
                } else if let precip = current["precipitationProbability"] as? Int {
                    precipProb = Double(precip)
                } else if let precip = current["precipitation"] as? Double {
                    precipProb = precip
                } else if let precip = current["precipitation"] as? Int {
                    precipProb = Double(precip)
                } else if let precip = current["rain"] as? Double {
                    precipProb = precip * 100 // Convert to percentage
                } else if let precip = current["rain"] as? Int {
                    precipProb = Double(precip)
                }
                
                // Parse the time
                var time = Date()
                if let timeString = current["time"] as? String {
                    // Try multiple date formats - handle each type separately
                    let iso8601Formatter = ISO8601DateFormatter()
                    if let parsedTime = iso8601Formatter.date(from: timeString) {
                        time = parsedTime
                        logger.notice("📅 Parsed date with ISO8601 format")
                    } else {
                        // Try other date formats
                        let customFormatters = [
                            DateFormatter.with(format: "yyyy-MM-dd'T'HH:mm:ssZ"),
                            DateFormatter.with(format: "yyyy-MM-dd HH:mm:ss")
                        ]
                        
                        for formatter in customFormatters {
                            if let parsedTime = formatter.date(from: timeString) {
                                time = parsedTime
                                logger.notice("📅 Parsed date with custom format")
                                break
                            }
                        }
                    }
                } else if let timeInterval = current["time"] as? TimeInterval {
                    time = Date(timeIntervalSince1970: timeInterval)
                } else if let timeInt = current["time"] as? Int {
                    time = Date(timeIntervalSince1970: TimeInterval(timeInt))
                }
                
                logger.notice("🌡️ Parsed temperature: \(temperatureValue)°F")
                logger.notice("☁️ Parsed cloud cover: \(cloudCover)%")
                logger.notice("💨 Parsed wind speed: \(windSpeed) mph")
                logger.notice("🌧️ Parsed precipitation: \(precipProb)%")
                
                // Create weather data entry
                let weather = WeatherWidgetEntry.WeatherData(
                    time: time,
                    temperature: temperatureValue,
                    cloudCover: cloudCover,
                    windSpeed: windSpeed,
                    precipitationProbability: precipProb
                )
                
                // Create successful entry
                let entry = WeatherWidgetEntry(
                    date: Date(),
                    weatherData: weather,
                    error: nil,
                    bridgeImage: bridgeImageData
                )
                
                completion(entry)
                logger.notice("✅ Timeline created with valid weather data")
                return
            }
        }
        
        // If we get here, we couldn't load or parse the data
        logger.error("❌ Failed to load or parse weather data")
        let entry = WeatherWidgetEntry(
            date: Date(),
            weatherData: nil,
            error: "No weather data available",
            bridgeImage: nil
        )
        completion(entry)
    }
}

// MARK: - Widget View
struct WidgetView: View {
    var entry: WeatherWidgetEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        ZStack {
            // Background
            if let imageData = entry.bridgeImage, 
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
            
            // Content overlay
            VStack(spacing: 6) {
                if let weather = entry.weatherData {
                    // Display actual weather data
                    Text("GGB Weather")
                        .font(.caption)
                        .fontWeight(.bold)
                    #if os(iOS)
                    Text("🌡️ \(Int(weather.temperature))°F")
                        .font(.system(size: family == .systemSmall ? 14 : 16))
                    Text("💨 \(Int(weather.windSpeed)) mph")
                        .font(.system(size: family == .systemSmall ? 14 : 16))
                    Text("🌧️ \(Int(weather.precipitationProbability))%")
                        .font(.system(size: family == .systemSmall ? 14 : 16))
                    #else
                    Text("🌡️ \(Int(weather.temperature))°F")
                        .font(.system(size: 14))
                    Text("💨 \(Int(weather.windSpeed)) mph")
                        .font(.system(size: 14))
                    Text("🌧️ \(Int(weather.precipitationProbability))%")
                        .font(.system(size: 14))
                    #endif
                } else if let error = entry.error {
                    // Display error with more guidance
                    VStack(spacing: 4) {
                        Text("GGB Weather")
                            .font(.caption)
                            .fontWeight(.bold)
                        Text("⚠️ \(error)")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Text("Try opening the app to refresh data")
                            .font(.caption2)
                            .padding(.top, 2)
                    }
                } else {
                    // Display placeholder
                    Text("Loading...")
                }
            }
            .padding()
            .foregroundColor(.white)
        }
        .onAppear {
            // Request a refresh when widget becomes visible
            #if os(iOS)
            WidgetCenter.shared.reloadTimelines(ofKind: "GGBWatchWidget")
            #endif
        }
    }
}

// MARK: - Widget Configuration
struct GGBWatchWidget: Widget {
    private let kind = "GGBWatchWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WeatherWidgetTimelineProvider()
        ) { entry in
            WidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "ggbweather://refresh"))
        }
        .configurationDisplayName("GGB Weather")
        .description("Current Golden Gate Bridge weather")
        #if os(iOS)
        .supportedFamilies([
            // iOS Widgets
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge
        ])
        #else
        .supportedFamilies([
            // Watch Widgets
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
        #endif
    }
}

// MARK: - Previews
struct GGBWatchWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            let entry = WeatherWidgetEntry(
                date: Date(),
                weatherData: WeatherWidgetEntry.WeatherData(
                    time: Date(),
                    temperature: 68,
                    cloudCover: 25,
                    windSpeed: 12,
                    precipitationProbability: 15
                ),
                error: nil as String?,
                bridgeImage: nil as Data?
            )
            
            WidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
            
            WidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
        }
    }
}

// MARK: - Widget Refresh Intent
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Weather Data"
    static var description: IntentDescription = IntentDescription("Refreshes the GGB Weather widget data")
    
    func perform() async throws -> some IntentResult {
        // Force widget refresh
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: "GGBWatchWidget")
        #else
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return .result()
    }
}

@main
struct GGBWatchWidgets: WidgetBundle {
    var body: some Widget {
        GGBWatchWidget()
    }
}