import WidgetKit
import SwiftUI
import os

struct Provider: TimelineProvider {
    private let logger = Logger(subsystem: "generouscorp.ggb.ggbweather", category: "WatchWidget")
    private let dataInteractor = SharedDataInteractor()
    
    func placeholder(in context: Context) -> WeatherEntry {
        logger.notice("📱 Providing placeholder entry")
        return WeatherEntry(date: Date(), weatherData: nil, error: nil)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> ()) {
        logger.notice("📸 Getting snapshot...")
        Task {
            do {
                if let cachedData = try await dataInteractor.loadWeatherData() {
                    logger.notice("✅ Snapshot loaded \(cachedData.weatherData.count) weather items")
                    completion(WeatherEntry(date: Date(), weatherData: cachedData.weatherData, error: nil))
                } else {
                    logger.error("❌ No data available for snapshot")
                    completion(WeatherEntry(date: Date(), weatherData: nil, error: "No data available"))
                }
            } catch {
                logger.error("❌ Failed to load snapshot: \(error.localizedDescription)")
                completion(WeatherEntry(date: Date(), weatherData: nil, error: error.localizedDescription))
            }
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> ()) {
        logger.notice("⏰ Getting timeline...")
        Task {
            do {
                if let cachedData = try await dataInteractor.loadWeatherData() {
                    logger.notice("✅ Timeline loaded \(cachedData.weatherData.count) weather items")
                    let entry = WeatherEntry(date: Date(), weatherData: cachedData.weatherData, error: nil)
                    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
                    logger.notice("📅 Next update scheduled for: \(nextUpdate)")
                    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
                } else {
                    logger.error("❌ No data available for timeline")
                    let entry = WeatherEntry(date: Date(), weatherData: nil, error: "No data available")
                    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
                }
            } catch {
                logger.error("❌ Failed to load timeline: \(error.localizedDescription)")
                let entry = WeatherEntry(date: Date(), weatherData: nil, error: error.localizedDescription)
                completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
            }
        }
    }
} 