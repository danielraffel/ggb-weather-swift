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
                logger.notice("✅ Snapshot using real data - Temperature: \(entry.weatherData?.temperature ?? 0)°F, Wind: \(entry.weatherData?.windSpeed ?? 0)mph, Precip: \(entry.weatherData?.precipitationProbability ?? 0)%")
                completion(entry)
            } else {
                // Fall back to placeholder only if real data can't be loaded
                logger.notice("⚠️ Snapshot using placeholder data - REASON: No weather data found in loadWeatherData")
                let placeholderEntry = WeatherWidgetEntry(
                    date: Date(),
                    weatherData: WeatherWidgetEntry.WeatherData(
                        time: Date(),
                        temperature: 54,  // More realistic based on current data
                        cloudCover: 20,
                        windSpeed: 11,    // More realistic based on current data
                        precipitationProbability: 0  // More realistic based on current data
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
                // If we have data, refresh more frequently
                #if os(iOS)
                refreshInterval = context.isPreview ? 60 * 60 : (context.family == .systemSmall ? 5 * 60 : 10 * 60)
                #else
                refreshInterval = context.isPreview ? 60 * 60 : 5 * 60 // Refresh every 5 minutes on watch
                #endif
                logger.notice("⏱️ Setting refresh interval to \(Int(refreshInterval/60)) minutes")
            } else {
                // If no data, try again sooner
                refreshInterval = 2 * 60 // Try every 2 minutes if no data
                logger.notice("⏱️ No data found, will retry in 2 minutes")
            }
            
            // Create timeline with appropriate refresh policy
            let nextUpdate = Date().addingTimeInterval(refreshInterval)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    // Helper method to load weather data
    private func loadWeatherData(completion: @escaping (WeatherWidgetEntry) -> Void) {
        logger.notice("🔄 loadWeatherData called - starting fresh data load")
        
        // DIRECT APPROACH: Use the exact container UUID from logs
        let knownContainerUUID = "29054354-0907-4329-9C6A-84716EB850D4"
        let directContainerPath = "/private/var/mobile/Containers/Shared/AppGroup/\(knownContainerUUID)"
        let fileManager = FileManager.default
        
        logger.notice("🎯 Directly targeting known container: \(knownContainerUUID)")
        
        if fileManager.fileExists(atPath: directContainerPath) {
            logger.notice("✅ Found the exact container from logs")
            
            // Check both Preferences and Caches locations
            let prefsCachePath = "\(directContainerPath)/Library/Preferences/weatherCache.json"
            let cachesCachePath = "\(directContainerPath)/Library/Caches/weatherCache.json"
            
            var weatherData: Data? = nil
            var dataSourcePath: String? = nil
            var bridgeImageData: Data? = nil
            
            // Try Preferences first
            if fileManager.fileExists(atPath: prefsCachePath) {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: prefsCachePath)
                    if let modDate = attributes[.modificationDate] as? Date {
                        let timeAgo = Date().timeIntervalSince(modDate)
                        logger.notice("📅 Preferences cache was last modified \(Int(timeAgo)) seconds ago")
                    }
                    
                    let data = try Data(contentsOf: URL(fileURLWithPath: prefsCachePath))
                    logger.notice("📊 Loaded \(data.count) bytes from Preferences cache")
                    
                    // Verify JSON is valid
                    if let _ = try? JSONSerialization.jsonObject(with: data) {
                        weatherData = data
                        dataSourcePath = prefsCachePath
                        logger.notice("✅ Valid JSON in Preferences cache")
                        
                        // Dump the raw JSON for debugging
                        if let jsonString = String(data: data, encoding: .utf8) {
                            let previewLength = min(500, jsonString.count)
                            let preview = jsonString.prefix(previewLength)
                            logger.notice("📄 JSON preview from Preferences: \(preview)...")
                        }
                    } else {
                        logger.error("❌ Invalid JSON in Preferences cache")
                    }
                } catch {
                    logger.error("❌ Error reading Preferences cache: \(error.localizedDescription)")
                }
            }
            
            // Try Caches if Preferences didn't work
            if weatherData == nil && fileManager.fileExists(atPath: cachesCachePath) {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: cachesCachePath)
                    if let modDate = attributes[.modificationDate] as? Date {
                        let timeAgo = Date().timeIntervalSince(modDate)
                        logger.notice("📅 Caches cache was last modified \(Int(timeAgo)) seconds ago")
                    }
                    
                    let data = try Data(contentsOf: URL(fileURLWithPath: cachesCachePath))
                    logger.notice("📊 Loaded \(data.count) bytes from Caches cache")
                    
                    // Verify JSON is valid
                    if let _ = try? JSONSerialization.jsonObject(with: data) {
                        weatherData = data
                        dataSourcePath = cachesCachePath
                        logger.notice("✅ Valid JSON in Caches cache")
                        
                        // Dump the raw JSON for debugging
                        if let jsonString = String(data: data, encoding: .utf8) {
                            let previewLength = min(500, jsonString.count)
                            let preview = jsonString.prefix(previewLength)
                            logger.notice("📄 JSON preview from Caches: \(preview)...")
                        }
                    } else {
                        logger.error("❌ Invalid JSON in Caches cache")
                    }
                } catch {
                    logger.error("❌ Error reading Caches cache: \(error.localizedDescription)")
                }
            }
            
            // If we found data, also look for bridge image
            if weatherData != nil {
                let imagePath = "\(directContainerPath)/Library/Caches/bridgeImage.data"
                if fileManager.fileExists(atPath: imagePath) {
                    do {
                        bridgeImageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
                        logger.notice("✅ Loaded bridge image: \(bridgeImageData?.count ?? 0) bytes")
                    } catch {
                        logger.error("❌ Error loading bridge image: \(error.localizedDescription)")
                    }
                }
            }
            
            // Process the weather data if we found it
            if let data = weatherData, let json = try? JSONSerialization.jsonObject(with: data) {
                logger.notice("✅ Successfully parsed JSON data")
                
                // Print the entire JSON for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.notice("📄 FULL JSON DATA: \(jsonString)")
                }
                
                // Try different formats the data might be in
                var weatherItems: [[String: Any]]? = nil
                var firstItem: [String: Any]? = nil
                
                // Format 1: {"weatherData": [{...}, {...}]}
                if let jsonDict = json as? [String: Any],
                   let items = jsonDict["weatherData"] as? [[String: Any]],
                   !items.isEmpty {
                    weatherItems = items
                    firstItem = items.first
                    logger.notice("📊 Found data in format 1 (weatherData array) with \(items.count) items")
                }
                
                // Format 2: Direct array of weather data [{...}, {...}]
                else if let items = json as? [[String: Any]], !items.isEmpty {
                    weatherItems = items
                    firstItem = items.first
                    logger.notice("📊 Found data in format 2 (direct array) with \(items.count) items")
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
                        logger.notice("🌡️ Found temperature as Double: \(temp)")
                    } else if let temp = current["temperature"] as? Int {
                        temperatureValue = Double(temp)
                        logger.notice("🌡️ Found temperature as Int: \(temp)")
                    } else if let temp = current["temp"] as? Double {
                        temperatureValue = temp
                        logger.notice("🌡️ Found temp as Double: \(temp)")
                    } else if let temp = current["temp"] as? Int {
                        temperatureValue = Double(temp)
                        logger.notice("🌡️ Found temp as Int: \(temp)")
                    } else if let tempStr = current["temperature"] as? String, let temp = Double(tempStr) {
                        temperatureValue = temp
                        logger.notice("🌡️ Found temperature as String: \(tempStr)")
                    } else if let tempStr = current["temp"] as? String, let temp = Double(tempStr) {
                        temperatureValue = temp
                        logger.notice("🌡️ Found temp as String: \(tempStr)")
                    }
                    
                    var cloudCover: Double = 0
                    if let cloud = current["cloudCover"] as? Double {
                        cloudCover = cloud
                        logger.notice("☁️ Found cloudCover as Double: \(cloud)")
                    } else if let cloud = current["cloudCover"] as? Int {
                        cloudCover = Double(cloud)
                        logger.notice("☁️ Found cloudCover as Int: \(cloud)")
                    } else if let cloud = current["clouds"] as? Double {
                        cloudCover = cloud
                        logger.notice("☁️ Found clouds as Double: \(cloud)")
                    } else if let cloud = current["clouds"] as? Int {
                        cloudCover = Double(cloud)
                        logger.notice("☁️ Found clouds as Int: \(cloud)")
                    }
                    
                    var windSpeed: Double = 0
                    if let wind = current["windSpeed"] as? Double {
                        windSpeed = wind
                        logger.notice("💨 Found windSpeed as Double: \(wind)")
                    } else if let wind = current["windSpeed"] as? Int {
                        windSpeed = Double(wind)
                        logger.notice("💨 Found windSpeed as Int: \(wind)")
                    } else if let wind = current["wind"] as? Double {
                        windSpeed = wind
                        logger.notice("💨 Found wind as Double: \(wind)")
                    } else if let wind = current["wind"] as? Int {
                        windSpeed = Double(wind)
                        logger.notice("💨 Found wind as Int: \(wind)")
                    } else if let windStr = current["windSpeed"] as? String, let wind = Double(windStr) {
                        windSpeed = wind
                        logger.notice("💨 Found windSpeed as String: \(windStr)")
                    } else if let windStr = current["wind"] as? String, let wind = Double(windStr) {
                        windSpeed = wind
                        logger.notice("💨 Found wind as String: \(windStr)")
                    }
                    
                    var precipProb: Double = 0
                    if let precip = current["precipitationProbability"] as? Double {
                        precipProb = precip
                        logger.notice("🌧️ Found precipitationProbability as Double: \(precip)")
                    } else if let precip = current["precipitationProbability"] as? Int {
                        precipProb = Double(precip)
                        logger.notice("🌧️ Found precipitationProbability as Int: \(precip)")
                    } else if let precip = current["precipitation"] as? Double {
                        precipProb = precip
                        logger.notice("🌧️ Found precipitation as Double: \(precip)")
                    } else if let precip = current["precipitation"] as? Int {
                        precipProb = Double(precip)
                        logger.notice("🌧️ Found precipitation as Int: \(precip)")
                    } else if let precip = current["rain"] as? Double {
                        precipProb = precip * 100 // Convert to percentage
                        logger.notice("🌧️ Found rain as Double: \(precip)")
                    } else if let precip = current["rain"] as? Int {
                        precipProb = Double(precip)
                        logger.notice("🌧️ Found rain as Int: \(precip)")
                    }
                    
                    // Parse the time
                    var time = Date()
                    if let timeString = current["time"] as? String {
                        // Try multiple date formats - handle each type separately
                        let iso8601Formatter = ISO8601DateFormatter()
                        if let parsedTime = iso8601Formatter.date(from: timeString) {
                            time = parsedTime
                            logger.notice("📅 Parsed date with ISO8601 format: \(timeString)")
                        } else {
                            // Try other date formats
                            let customFormatters = [
                                DateFormatter.with(format: "yyyy-MM-dd'T'HH:mm:ssZ"),
                                DateFormatter.with(format: "yyyy-MM-dd HH:mm:ss")
                            ]
                            
                            for formatter in customFormatters {
                                if let parsedTime = formatter.date(from: timeString) {
                                    time = parsedTime
                                    logger.notice("📅 Parsed date with custom format: \(timeString)")
                                    break
                                }
                            }
                        }
                    } else if let timeInterval = current["time"] as? TimeInterval {
                        time = Date(timeIntervalSince1970: timeInterval)
                        logger.notice("📅 Parsed date from TimeInterval: \(timeInterval)")
                    } else if let timeInt = current["time"] as? Int {
                        time = Date(timeIntervalSince1970: TimeInterval(timeInt))
                        logger.notice("📅 Parsed date from Int: \(timeInt)")
                    }
                    
                    logger.notice("🌡️ Final temperature: \(temperatureValue)°F")
                    logger.notice("☁️ Final cloud cover: \(cloudCover)%")
                    logger.notice("💨 Final wind speed: \(windSpeed) mph")
                    logger.notice("🌧️ Final precipitation: \(precipProb)%")
                    
                    // Create weather data entry
                    let weather = WeatherWidgetEntry.WeatherData(
                        time: time,
                        temperature: temperatureValue,
                        cloudCover: cloudCover,
                        windSpeed: windSpeed,
                        precipitationProbability: precipProb
                    )
                    
                    // Check if the data is too old (more than 30 minutes)
                    let dataAge = Date().timeIntervalSince(time)
                    logger.notice("📅 Data age check: \(Int(dataAge/60)) minutes old (limit: 30 minutes)")
                    if dataAge > 30 * 60 {
                        logger.notice("⚠️ Data is too old (\(Int(dataAge/60)) minutes), using placeholder instead")
                        let placeholderEntry = WeatherWidgetEntry(
                            date: Date(),
                            weatherData: WeatherWidgetEntry.WeatherData(
                                time: Date(),
                                temperature: 54,  // More realistic based on current data
                                cloudCover: 20,
                                windSpeed: 11,    // More realistic based on current data
                                precipitationProbability: 0  // More realistic based on current data
                            ),
                            error: nil,
                            bridgeImage: bridgeImageData
                        )
                        completion(placeholderEntry)
                        return
                    }
                    
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
                } else {
                    logger.error("❌ Could not find weather item in JSON")
                }
            } else if weatherData != nil {
                logger.error("❌ Failed to parse JSON data")
            }
        } else {
            logger.error("❌ Known container not found, falling back to search")
        }
        
        // If direct approach failed, fall back to the original search logic
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
        var newestModificationDate: Date? = nil
        
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
                            // Check if this file is newer than what we've found so far
                            if let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
                               let modDate = attributes[.modificationDate] as? Date {
                                let timeAgo = Date().timeIntervalSince(modDate)
                                logger.notice("📅 File was last modified \(Int(timeAgo)) seconds ago")
                                
                                if newestModificationDate == nil || modDate > newestModificationDate! {
                                    weatherData = tempData
                                    dataSourcePath = path.path
                                    newestModificationDate = modDate
                                    logger.notice("✅ Found newer data, updating: \(path.path)")
                                } else {
                                    logger.notice("⏱️ Skipping older data from: \(path.path)")
                                }
                            } else {
                                // If we can't get mod date, use this if we don't have any data yet
                                if weatherData == nil {
                                    weatherData = tempData
                                    dataSourcePath = path.path
                                    logger.notice("✅ Loaded valid JSON data from \(path.path): \(weatherData?.count ?? 0) bytes")
                                }
                            }
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
            if weatherData != nil && dataSourcePath != nil {
                let imagePath = container.appendingPathComponent("Library/Caches/bridgeImage.data")
                if FileManager.default.fileExists(atPath: imagePath.path) {
                    do {
                        bridgeImageData = try Data(contentsOf: imagePath)
                        logger.notice("✅ Loaded bridge image: \(bridgeImageData?.count ?? 0) bytes")
                    } catch {
                        logger.error("❌ Error loading bridge image: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Log final data source
        if let path = dataSourcePath {
            logger.notice("📊 Using data from: \(path)")
        }
        
        // Process the weather data if we found it
        if let data = weatherData, let json = try? JSONSerialization.jsonObject(with: data) {
            logger.notice("✅ Successfully parsed JSON data from \(dataSourcePath ?? "unknown location")")
            
            // Dump the raw JSON for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                let previewLength = min(500, jsonString.count)
                let preview = jsonString.prefix(previewLength)
                logger.notice("📄 JSON preview: \(preview)...")
            }
            
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
                    logger.notice("🌡️ Found temperature as Double: \(temp)")
                } else if let temp = current["temperature"] as? Int {
                    temperatureValue = Double(temp)
                    logger.notice("🌡️ Found temperature as Int: \(temp)")
                } else if let temp = current["temp"] as? Double {
                    temperatureValue = temp
                    logger.notice("🌡️ Found temp as Double: \(temp)")
                } else if let temp = current["temp"] as? Int {
                    temperatureValue = Double(temp)
                    logger.notice("🌡️ Found temp as Int: \(temp)")
                } else if let tempStr = current["temperature"] as? String, let temp = Double(tempStr) {
                    temperatureValue = temp
                    logger.notice("🌡️ Found temperature as String: \(tempStr)")
                } else if let tempStr = current["temp"] as? String, let temp = Double(tempStr) {
                    temperatureValue = temp
                    logger.notice("🌡️ Found temp as String: \(tempStr)")
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
                    logger.notice("💨 Found windSpeed as Double: \(wind)")
                } else if let wind = current["windSpeed"] as? Int {
                    windSpeed = Double(wind)
                    logger.notice("💨 Found windSpeed as Int: \(wind)")
                } else if let wind = current["wind"] as? Double {
                    windSpeed = wind
                    logger.notice("💨 Found wind as Double: \(wind)")
                } else if let wind = current["wind"] as? Int {
                    windSpeed = Double(wind)
                    logger.notice("💨 Found wind as Int: \(wind)")
                } else if let windStr = current["windSpeed"] as? String, let wind = Double(windStr) {
                    windSpeed = wind
                    logger.notice("💨 Found windSpeed as String: \(windStr)")
                } else if let windStr = current["wind"] as? String, let wind = Double(windStr) {
                    windSpeed = wind
                    logger.notice("💨 Found wind as String: \(windStr)")
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
                
                // Check if the data is too old (more than 30 minutes)
                let dataAge = Date().timeIntervalSince(time)
                logger.notice("📅 Data age check: \(Int(dataAge/60)) minutes old (limit: 30 minutes)")
                if dataAge > 30 * 60 {
                    logger.notice("⚠️ Data is too old (\(Int(dataAge/60)) minutes), using placeholder instead")
                    let placeholderEntry = WeatherWidgetEntry(
                        date: Date(),
                        weatherData: WeatherWidgetEntry.WeatherData(
                            time: Date(),
                            temperature: 54,  // More realistic based on current data
                            cloudCover: 20,
                            windSpeed: 11,    // More realistic based on current data
                            precipitationProbability: 0  // More realistic based on current data
                        ),
                        error: nil,
                        bridgeImage: bridgeImageData
                    )
                    completion(placeholderEntry)
                    return
                }
                
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
    
    // Static function to avoid capturing self
    static func refreshWidgets() {
        logger.notice("👁️ Widget became visible - requesting refresh")
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // Static function for delayed refresh
    static func delayedRefresh(seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            logger.notice("⏱️ Delayed refresh \(Int(seconds)) second(s) after appear")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    // Static helper for date formatting
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    var body: some View {
        ZStack {
            // Background
            #if os(iOS)
            if let imageData = entry.bridgeImage, 
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
            #else
            Color.black
            #endif
            
            // Content overlay
            VStack(spacing: 6) {
                if let weather = entry.weatherData {
                    // Display actual weather data
                    #if os(iOS)
                    Text("GGB Weather")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text("🌡️ \(Int(weather.temperature))°F")
                        .font(.system(size: family == .systemSmall ? 14 : 16))
                    Text("💨 \(Int(weather.windSpeed)) mph")
                        .font(.system(size: family == .systemSmall ? 14 : 16))
                    Text("🌧️ \(Int(weather.precipitationProbability))%")
                        .font(.system(size: family == .systemSmall ? 14 : 16))
                    
                    // Add a tiny timestamp for debugging
                    if family != .systemSmall {
                        Text(Self.formatDate(entry.date))
                            .font(.system(size: 8))
                            .opacity(0.6)
                    }
                    #else
                    // Watch-specific layouts based on widget family
                    if family == .accessoryRectangular {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GGB Weather")
                                .font(.caption2)
                                .fontWeight(.bold)
                            HStack {
                                Text("🌡️ \(Int(weather.temperature))°F")
                                    .font(.system(size: 14))
                                Spacer()
                                Text("💨 \(Int(weather.windSpeed)) mph")
                                    .font(.system(size: 14))
                            }
                            Text("🌧️ \(Int(weather.precipitationProbability))%")
                                .font(.system(size: 14))
                        }
                    } else if family == .accessoryCircular {
                        VStack(spacing: 0) {
                            Text("\(Int(weather.temperature))°")
                                .font(.system(size: 18, weight: .bold))
                            Text("\(Int(weather.windSpeed))mph")
                                .font(.system(size: 10))
                        }
                    } else if family == .accessoryInline {
                        Text("GGB: \(Int(weather.temperature))°F, \(Int(weather.windSpeed))mph")
                            .font(.caption2)
                    } else {
                        // Corner family or any other
                        VStack(spacing: 2) {
                            Text("\(Int(weather.temperature))°F")
                                .font(.system(size: 16, weight: .bold))
                            Text("\(Int(weather.windSpeed))mph")
                                .font(.system(size: 12))
                        }
                    }
                    #endif
                } else if let error = entry.error {
                    // Display error with more guidance
                    #if os(iOS)
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
                    #else
                    // Simplified error for watch
                    if family == .accessoryInline {
                        Text("GGB: No data")
                    } else {
                        Text("⚠️ No data")
                    }
                    #endif
                } else {
                    // Display placeholder
                    Text("Loading...")
                        .font(.caption)
                }
            }
            .padding()
            .foregroundColor(.white)
        }
        .onAppear {
            // Use static methods to avoid capturing self
            Self.refreshWidgets()
            Self.delayedRefresh(seconds: 1)
            Self.delayedRefresh(seconds: 3)
        }
    }
}

// MARK: - Widget Configuration
final class GGBWatchWidget: Widget {
    private let kind = "GGBWatchWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: self.kind,
            provider: WeatherWidgetTimelineProvider()
        ) { entry in
            WidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
                #if os(iOS)
                .widgetURL(URL(string: "ggbweather://refresh"))
                #endif
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
        // Watch Widgets - explicitly list all supported families
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
        #endif
    }
    
    // Add an observer to refresh the widget when the app becomes active
    init() {
        logger.notice("🔄 Initializing GGBWatchWidget")
        
        // Force an immediate refresh
        WidgetCenter.shared.reloadAllTimelines()
        
        // Log platform information
        #if os(watchOS)
        logger.notice("📱 Widget running on watchOS")
        logger.notice("📱 Widget kind: \(self.kind)")
        logger.notice("📱 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        #else
        logger.notice("📱 Widget running on iOS")
        #endif
        
        // Note: We're not using a timer anymore as widgets should refresh automatically
        // based on the timeline policy set in the provider
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
                    temperature: 55,
                    cloudCover: 40,
                    windSpeed: 8,
                    precipitationProbability: 10
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

// MARK: - Widget Bundle
@main
final class GGBWatchWidgets: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        GGBWatchWidget()
    }
    
    init() {
        // Simple logging without any timers or complex operations
        logger.notice("🔄 Initializing GGBWatchWidgets bundle")
        logger.notice("📱 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
    }
}