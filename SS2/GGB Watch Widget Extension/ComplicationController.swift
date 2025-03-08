import ClockKit
import SwiftUI
import WidgetKit
import os

class ComplicationController: NSObject, CLKComplicationDataSource {
    private let dataInteractor = SharedDataInteractor()
    private var cachedWeatherData: CachedWeatherData?
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "ComplicationController")
    
    override init() {
        super.init()
        // Load cached data on initialization
        Task {
            cachedWeatherData = try? await dataInteractor.loadWeatherData()
        }
    }
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Create a timeline entry for the current time
        let timelineEntry = createTimelineEntry(for: complication, date: Date())
        handler(timelineEntry)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Create timeline entries for future updates
        let entries = (0..<limit).compactMap { index -> CLKComplicationTimelineEntry? in
            let entryDate = date.addingTimeInterval(TimeInterval(index * 3600))
            return createTimelineEntry(for: complication, date: entryDate)
        }
        handler(entries)
    }
    
    private func createTimelineEntry(for complication: CLKComplication, date: Date) -> CLKComplicationTimelineEntry? {
        guard let template = createTemplate(for: complication) else { return nil }
        return CLKComplicationTimelineEntry(date: date, complicationTemplate: template)
    }
    
    private func createTemplate(for complication: CLKComplication) -> CLKComplicationTemplate? {
        guard let weatherData = cachedWeatherData?.weatherData.first else {
            logger.error("❌ No weather data available for complication")
            return nil
        }
        
        let widgetWeatherData: WeatherWidgetEntry.WeatherData = .init(
            time: weatherData.time,
            temperature: weatherData.temperature,
            cloudCover: weatherData.cloudCover,
            windSpeed: weatherData.windSpeed,
            precipitationProbability: weatherData.precipitationProbability
        )
        
        let entry = WeatherWidgetEntry(
            date: Date(),
            weatherData: widgetWeatherData,
            error: nil as String?,
            bridgeImage: cachedWeatherData?.bridgeImage as Data?
        )
        
        switch complication.family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularView(
                WidgetView(entry: entry)
            )
            
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularFullView(
                WidgetView(entry: entry)
            )
            
        default:
            logger.notice("⚠️ Unsupported complication family: \(String(describing: complication.family))")
            return nil
        }
    }
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        handler(createTemplate(for: complication))
    }
} 