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

@main
struct GGB_Watch_Widget_Extension: Widget {
    private let kind = "GGB_Watch_Widget_Extension"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherWidgetTimelineProvider()) { entry in
            GGB_Watch_Widget_ExtensionEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
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
            } else if let weather = entry.weatherData {
                VStack(spacing: 2) {
                    Text("\(Int(weather.temperature))°")
                        .font(.system(.body, design: .rounded))
                        .bold()
                    
                    Text("\(Int(weather.windSpeed))mph")
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
            }
        }
    }
}

#Preview(as: .accessoryCircular) {
    GGB_Watch_Widget_Extension()
} timeline: {
    let weatherData = WeatherData(
        time: Date(),
        temperature: 72,
        cloudCover: 30,
        windSpeed: 15,
        precipitationProbability: 20
    )
    
    // Create a sample bridge image
    let sampleImage = UIImage(systemName: "bridge")?.withTintColor(.orange)
    let bridgeImageData = sampleImage?.pngData()
    
    let entry1 = WeatherWidgetEntry(
        date: Date(),
        weatherData: weatherData,
        error: nil,
        bridgeImage: bridgeImageData
    )
    
    let entry2 = WeatherWidgetEntry(
        date: Date(),
        weatherData: nil,
        error: "No data",
        bridgeImage: nil
    )
    
    return [entry1, entry2]
}