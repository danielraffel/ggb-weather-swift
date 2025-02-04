import ClockKit
import SwiftUI
import WidgetKit

class ComplicationController: NSObject, CLKComplicationDataSource {
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
        switch complication.family {
        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularView(
                GGB_Watch_Widget_ExtensionEntryView(entry: WeatherWidgetEntry(
                    date: Date(),
                    weatherData: WeatherData(
                        time: Date(),
                        temperature: 72,
                        cloudCover: 30,
                        windSpeed: 15,
                        precipitationProbability: 20
                    ),
                    error: nil
                ))
            )
            return template
            
        case .graphicRectangular:
            let template = CLKComplicationTemplateGraphicRectangularFullView(
                GGB_Watch_Widget_ExtensionEntryView(entry: WeatherWidgetEntry(
                    date: Date(),
                    weatherData: WeatherData(
                        time: Date(),
                        temperature: 72,
                        cloudCover: 30,
                        windSpeed: 15,
                        precipitationProbability: 20
                    ),
                    error: nil
                ))
            )
            return template
            
        default:
            return nil
        }
    }
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        handler(createTemplate(for: complication))
    }
} 