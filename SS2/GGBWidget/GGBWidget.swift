//
//  GGBWidget.swift
//  GGBWidget
//
//  Created by Daniel Raffel on 1/31/25.
//

import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        let placeholderTime = BestVisitTime(
            time: Date(),
            temperature: 47.1,
            precipitationProbability: 6.0,
            cloudCover: 99.0,
            windSpeed: 3.4,
            score: 0
        )
        return WeatherEntry(
            date: Date(),
            bestTime: placeholderTime,
            secondBestTime: placeholderTime,
            imageData: nil
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> ()) {
        let entry = placeholder(in: context)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> ()) {
        Task {
            do {
                let interactor = WeatherInteractor()
                let weatherData = try await interactor.fetchWeatherData()
                let imageData = try? await fetchBridgeImage()
                
                // Calculate best time using existing logic
                let bestTimes = calculateBestTimes(from: weatherData)
                let entry = WeatherEntry(
                    date: Date(),
                    bestTime: bestTimes[0],
                    secondBestTime: bestTimes[1],
                    imageData: imageData
                )
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date(timeIntervalSinceNow: 3600))))
            }
        }
    }
    
    private func fetchBridgeImage() async throws -> Data {
        let url = URL(string: "https://raw.githubusercontent.com/danielraffel/ggb/main/ggb.screenshot.png")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
    
    private func calculateBestTimes(from weatherData: [WeatherData]) -> [BestVisitTime] {
        let filteredData = weatherData.filter { data in
            let hour = Calendar.current.component(.hour, from: data.time)
            return hour >= 6 && hour <= 20
        }
        
        return filteredData.map { data in
            let tempScore = data.temperature * 2
            let rainScore = 100 - data.precipitationProbability
            let cloudScore = (100 - data.cloudCover) / 2
            let windScore = (20 - data.windSpeed) / 2
            
            return BestVisitTime(
                time: data.time,
                temperature: data.temperature,
                precipitationProbability: data.precipitationProbability,
                cloudCover: data.cloudCover,
                windSpeed: data.windSpeed,
                score: tempScore + rainScore + cloudScore + windScore
            )
        }.sorted { $0.score > $1.score }
    }
}

struct WeatherEntry: TimelineEntry {
    let date: Date
    let bestTime: BestVisitTime
    let secondBestTime: BestVisitTime
    let imageData: Data?
}

struct GGBWidgetEntryView: View {
    var entry: Provider.Entry
    
    var body: some View {
        HStack(spacing: 0) {
            // Best Time (Left)
            VStack(alignment: .leading, spacing: 4) {
                Text("🥇 Best Time")
                    .font(.caption)
                    .foregroundColor(.yellow)
                
                Text(formatTime(entry.bestTime.time))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(entry.bestTime.temperature, specifier: "🌡️ %.1f")°F")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text("\(entry.bestTime.precipitationProbability, specifier: "🌧️ %.0f")% chance")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Second Best Time (Right)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Second Best 🥈")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text(formatTime(entry.secondBestTime.time))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(entry.secondBestTime.temperature, specifier: "%.1f")°F 🌡️")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text("\(entry.secondBestTime.precipitationProbability, specifier: "%.0f")% chance 🌧️")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .containerBackground(for: .widget) {
            if let imageData = entry.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .padding(.horizontal, -20)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

@main
struct GGBWidget: Widget {
    let kind: String = "GGBWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            GGBWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("GGB Best Time")
        .description("Shows the best time to cross the Golden Gate Bridge")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
