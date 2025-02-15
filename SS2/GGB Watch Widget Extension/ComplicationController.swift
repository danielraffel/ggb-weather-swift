import ClockKit
import SwiftUI
import WidgetKit

class ComplicationController: NSObject, CLKComplicationDataSource {
    private let dataInteractor = SharedDataInteractor()
    private var cachedWeatherData: CachedWeatherData?
    
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
        // Get first weather data item from cache
        guard let weatherData = cachedWeatherData?.weatherData.first else { 
            return nil 
        }
        
        switch complication.family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularView(
                GGB_Watch_Widget_ExtensionEntryView(entry: WeatherWidgetEntry(
                    date: Date(),
                    weatherData: weatherData,
                    error: nil,
                    bridgeImage: cachedWeatherData?.bridgeImage
                ))
            )
            
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularFullView(
                GGB_Watch_Widget_ExtensionEntryView(entry: WeatherWidgetEntry(
                    date: Date(),
                    weatherData: weatherData,
                    error: nil,
                    bridgeImage: cachedWeatherData?.bridgeImage
                ))
            )
            
        default:
            return nil
        }
    }
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        handler(createTemplate(for: complication))
    }
} 