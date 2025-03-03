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

private let logger = Logger(subsystem: "generouscorp.ggb", category: "Widget")

@main
struct GGB_Watch_Widget_Extension: Widget {
    private let kind = "GGB_Watch_Widget_Extension"
    
    init() {
        logger.notice("🔧 Widget initializing...")
        
        // Debug app group access
        let fileManager = FileManager.default
        var allContainers: [URL] = []
        
        // First, try the standard app group identifiers
        let appGroupIdentifiers = ["group.genco", "group.generouscorp.ggb"]
        for identifier in appGroupIdentifiers {
            if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                allContainers.append(containerURL)
                logger.notice("📂 Found container for \(identifier): \(containerURL.path)")
            }
        }
        
        // In simulator, we need to look in parent directories for other containers
        #if targetEnvironment(simulator)
        if let firstContainer = allContainers.first {
            logger.notice("🔍 Running in simulator, searching for additional containers...")
            
            // Get simulator root directory (6 levels up from container)
            let simulatorRoot = firstContainer.deletingLastPathComponent() // AppGroup
                .deletingLastPathComponent() // Shared
                .deletingLastPathComponent() // Containers
                .deletingLastPathComponent() // data
                .deletingLastPathComponent() // DeviceID
                .deletingLastPathComponent() // Devices
            
            logger.notice("📱 Simulator root: \(simulatorRoot.path)")
            
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
                                logger.notice("✅ Found additional container in simulator: \(group.path)")
                            }
                        }
                    }
                }
            }
        }
        #endif
        
        logger.notice("📂 Found \(allContainers.count) potential app group containers")
        
        // Check each container for valid data
        for container in allContainers {
            logger.notice("   📂 Checking container: \(container.path)")
            
            // Check for existing cache files
            let prefsPath = container.appendingPathComponent("Library/Preferences/weatherCache.json")
            let cachesPath = container.appendingPathComponent("Library/Caches/weatherCache.json")
            
            if fileManager.fileExists(atPath: prefsPath.path) {
                if let data = try? Data(contentsOf: prefsPath),
                   let cachedData = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                    logger.notice("✅ Found valid cache in Preferences (\(data.count) bytes)")
                    if let firstWeather = cachedData.weatherData.first {
                        logger.notice("🌡️ First weather entry: \(firstWeather.temperature)°, \(firstWeather.windSpeed)mph")
                    }
                } else {
                    logger.error("❌ Cache file in Preferences exists but cannot be read")
                }
            }
            if fileManager.fileExists(atPath: cachesPath.path) {
                if let data = try? Data(contentsOf: cachesPath),
                   let cachedData = try? JSONDecoder().decode(CachedWeatherData.self, from: data) {
                    logger.notice("✅ Found valid cache in Caches (\(data.count) bytes)")
                    if let firstWeather = cachedData.weatherData.first {
                        logger.notice("🌡️ First weather entry: \(firstWeather.temperature)°, \(firstWeather.windSpeed)mph")
                    }
                } else {
                    logger.error("❌ Cache file in Caches exists but cannot be read")
                }
            }
        }
        
        if allContainers.isEmpty {
            logger.error("❌ Could not access any app group containers")
        }
    }
    
    var body: some WidgetConfiguration {
        logger.notice("⚙️ Creating widget configuration...")
        let provider = WeatherWidgetTimelineProvider()
        
        // Create configuration
        let configuration = StaticConfiguration(kind: kind, provider: provider) { entry in
            GGB_Watch_Widget_ExtensionEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        
        // Log after creating the configuration
        logger.notice("✅ Widget configuration created")
        
        return configuration
            .configurationDisplayName("GGB Weather")
            .description("Shows current weather at Golden Gate Bridge")
            .supportedFamilies([
                .accessoryCircular,
                .accessoryRectangular,
                .accessoryInline,
                .accessoryCorner
            ])
    }
}

struct GGB_Watch_Widget_ExtensionEntryView: View {
    let entry: WeatherWidgetEntry
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "WidgetView")
    
    var body: some View {
        ZStack {
            if let bridgeImage = entry.bridgeImage {
                Image(uiImage: UIImage(data: bridgeImage) ?? UIImage())
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.7)
            }
            
            if let error = entry.error {
                Text(error)
                    .font(.caption2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.red)
            } else if let weather = entry.weatherData {
                VStack(spacing: 2) {
                    Text("\(String(format: "%.1f", weather.temperature))°F")
                        .font(.system(.body, design: .rounded))
                        .bold()
                    
                    Text("\(String(format: "%.1f", weather.windSpeed))mph")
                        .font(.system(.caption2, design: .rounded))
                    
                    if weather.precipitationProbability > 0 {
                        Text("\(Int(weather.precipitationProbability))%")
                            .font(.system(.caption2, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .shadow(radius: 2)
            } else {
                Text("Loading...")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .onAppear {
            logger.notice("🎨 Widget view appeared with \(entry.weatherData != nil ? "weather data" : "no weather data") and \(entry.error != nil ? "error: \(entry.error!)" : "no error")")
        }
    }
}

#Preview(as: .accessoryCircular) {
    GGB_Watch_Widget_Extension()
} timeline: {
    let weatherData = WeatherData(
        time: Date(),
        temperature: 72.5,
        cloudCover: 30,
        windSpeed: 15.2,
        precipitationProbability: 20
    )
    
    // Create a sample bridge image
    let sampleImage = UIImage(systemName: "cloud.sun")?.withTintColor(.orange)
    let bridgeImageData = sampleImage?.pngData()
    
    let entry = WeatherWidgetEntry(
        date: Date(),
        weatherData: weatherData,
        error: nil,
        bridgeImage: bridgeImageData
    )
    
    return [entry]
}