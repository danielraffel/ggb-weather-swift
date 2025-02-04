import WidgetKit
import SwiftUI
import Foundation
import os

// Remove SS2 typealias and use WeatherData directly
struct WeatherWidgetTimelineProvider: TimelineProvider {
    typealias Entry = WeatherWidgetEntry
    private let dataInteractor: SharedDataInteractorProtocol
    private let logger = Logger(subsystem: "generouscorp.SS2.ggbweather", category: "WidgetTimelineProvider")
    
    init(dataInteractor: SharedDataInteractorProtocol = SharedDataInteractor()) {
        self.dataInteractor = dataInteractor
        logger.notice("⌚️ Widget Timeline Provider initialized")
        
        // Debug app group path
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.generouscorp.SS2.ggbweather") {
            logger.notice("📂 App group container path: \(containerURL.path)")
        } else {
            logger.error("❌ Could not access app group container")
        }
    }
    
    func placeholder(in context: Context) -> WeatherWidgetEntry {
        logger.notice("📍 Providing placeholder entry")
        return WeatherWidgetEntry(date: Date(), weatherData: nil as WeatherData?, error: nil as String?)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        logger.notice("📸 Getting widget snapshot...")
        Task {
            do {
                let cachedData = try await dataInteractor.loadWeatherData()
                logger.notice("✅ Loaded cached data for snapshot. Items: \(cachedData?.weatherData.count ?? 0)")
                let entry = WeatherWidgetEntry(
                    date: Date(),
                    weatherData: cachedData?.weatherData.first,
                    error: nil as String?
                )
                completion(entry)
            } catch {
                logger.error("❌ Failed to load snapshot data: \(error.localizedDescription)")
                completion(WeatherWidgetEntry(
                    date: Date(),
                    weatherData: nil as WeatherData?,
                    error: error.localizedDescription
                ))
            }
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherWidgetEntry>) -> Void) {
        logger.notice("🕒 Getting widget timeline...")
        Task {
            do {
                let cachedData = try await dataInteractor.loadWeatherData()
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
                            error: nil as String?
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
                    weatherData: nil as WeatherData?,
                    error: error.localizedDescription
                )
                let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
                completion(timeline)
            }
        }
    }
}

struct WeatherWidgetEntry: TimelineEntry {
    let date: Date
    let weatherData: WeatherData?
    let error: String?
} 