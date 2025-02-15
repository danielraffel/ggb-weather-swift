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

// Remove SS2 typealias and use WeatherData directly
struct WeatherWidgetTimelineProvider: TimelineProvider {
    typealias Entry = WeatherWidgetEntry
    typealias Configuration = ConfigurationAppIntent
    
    private let dataInteractor: SharedDataInteractorProtocol
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "WidgetTimelineProvider")
    private let appGroupIdentifier = "group.genco"
    
    init(dataInteractor: SharedDataInteractorProtocol = SharedDataInteractor()) {
        self.dataInteractor = dataInteractor
        let identifier = appGroupIdentifier
        let logger = self.logger
        
        logger.notice("⌚️ Widget Timeline Provider initialized with group: \(identifier)")
        
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            logger.notice("📂 App group container path: \(containerURL.path)")
        } else {
            logger.error("❌ Could not access app group container: \(identifier)")
        }
    }
    
    func placeholder(in context: Context) -> WeatherWidgetEntry {
        logger.notice("📍 Providing placeholder entry")
        return WeatherWidgetEntry(date: Date(), weatherData: nil, error: nil, bridgeImage: nil)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        logger.notice("📸 Getting widget snapshot...")
        Task {
            do {
                let cachedData = try await dataInteractor.loadWeatherData(maxRetries: 3, retryDelay: 2.0)
                logger.notice("✅ Loaded cached data for snapshot. Items: \(cachedData?.weatherData.count ?? 0)")
                let entry = WeatherWidgetEntry(
                    date: Date(),
                    weatherData: cachedData?.weatherData.first,
                    error: nil,
                    bridgeImage: cachedData?.bridgeImage
                )
                completion(entry)
            } catch {
                logger.error("❌ Failed to load snapshot data: \(error.localizedDescription)")
                completion(WeatherWidgetEntry(
                    date: Date(),
                    weatherData: nil,
                    error: error.localizedDescription,
                    bridgeImage: nil
                ))
            }
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherWidgetEntry>) -> Void) {
        logger.notice("🕒 Getting widget timeline...")
        Task {
            do {
                let cachedData = try await dataInteractor.loadWeatherData(maxRetries: 3, retryDelay: 2.0)
                logger.notice("✅ Loaded cached data for timeline. Items: \(cachedData?.weatherData.count ?? 0)")
                let currentDate = Date()
                
                // Create entries for the next few hours
                let entries = cachedData?.weatherData
                    .filter { $0.time > currentDate }
                    .prefix(12)
                    .map { weatherData in
                        WeatherWidgetEntry(
                            date: weatherData.time,
                            weatherData: weatherData,
                            error: nil,
                            bridgeImage: cachedData?.bridgeImage
                        )
                    } ?? []
                
                logger.notice("📊 Created \(entries.count) timeline entries")
                let timeline = Timeline(
                    entries: entries.isEmpty ? [placeholder(in: context)] : entries,
                    policy: .after(currentDate.addingTimeInterval(15 * 60)) // Refresh every 15 minutes
                )
                
                completion(timeline)
            } catch {
                logger.error("❌ Failed to load timeline data: \(error.localizedDescription)")
                let entry = WeatherWidgetEntry(
                    date: Date(),
                    weatherData: nil,
                    error: error.localizedDescription,
                    bridgeImage: nil
                )
                let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
                completion(timeline)
            }
        }
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<Entry> {
        let entry = try? await getWeatherEntry()
        let entries = [entry ?? WeatherWidgetEntry(date: .now, weatherData: nil, error: "No data", bridgeImage: nil)]
        
        // Schedule next update in 15 minutes or sooner if in preview
        let nextUpdate = context.isPreview ? Date().addingTimeInterval(60) : Date().addingTimeInterval(15 * 60)
        
        logger.notice("📅 Created timeline with \(entries.count) entries, next update at \(nextUpdate)")
        return Timeline(entries: entries, policy: .after(nextUpdate))
    }
    
    private func getWeatherEntry() async throws -> WeatherWidgetEntry {
        do {
            if let cachedData = try await dataInteractor.loadWeatherData(maxRetries: 3, retryDelay: 2.0) {
                logger.notice("✅ Loaded cached data for widget")
                return WeatherWidgetEntry(
                    date: .now,
                    weatherData: cachedData.weatherData.first,
                    error: nil,
                    bridgeImage: cachedData.bridgeImage
                )
            }
            throw SharedDataError.cacheEmpty
        } catch {
            logger.error("❌ Widget data load failed: \(error.localizedDescription)")
            return WeatherWidgetEntry(
                date: .now,
                weatherData: nil,
                error: error.localizedDescription,
                bridgeImage: nil
            )
        }
    }
} 