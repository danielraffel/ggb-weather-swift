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

struct WeatherData: Identifiable {
    let id = UUID()
    let time: Date
    let temperature: Double
    let cloudCover: Double
    let windSpeed: Double
    let precipitationProbability: Double
}

@MainActor
final class WeatherInteractor: @unchecked Sendable {
    private let dateFormatter: DateFormatter
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        dateFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
    }
    
    func fetchWeatherData() async throws -> [WeatherData] {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=37.8199&longitude=-122.4783&hourly=temperature_2m,cloudcover,windspeed_10m,precipitation_probability&timezone=America/Los_Angeles&forecast_days=1&temperature_unit=fahrenheit"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        let formatter = self.dateFormatter
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
        
        let response = try decoder.decode(WeatherResponse.self, from: data)
        let hourly = response.hourly
        
        return zip(hourly.time.indices, hourly.time).map { index, time in
            WeatherData(
                time: time,
                temperature: hourly.temperature2m[index],
                cloudCover: hourly.cloudcover[index],
                windSpeed: hourly.windspeed10m[index] * 0.621371,
                precipitationProbability: hourly.precipitationProbability[index]
            )
        }
    }
}

struct WeatherResponse: Decodable {
    let hourly: HourlyData
}

struct HourlyData: Decodable {
    let time: [Date]
    let temperature2m: [Double]
    let cloudcover: [Double]
    let windspeed10m: [Double]
    let precipitationProbability: [Double]
}

struct WeatherEntry: TimelineEntry {
    let date: Date
    let currentWeather: WeatherData
    let imageData: Data?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        let placeholderWeather = WeatherData(
            time: Date(),
            temperature: 47.1,
            cloudCover: 99.0,
            windSpeed: 5.4,
            precipitationProbability: 6.0
        )
        
        return WeatherEntry(
            date: Date(),
            currentWeather: placeholderWeather,
            imageData: nil
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> ()) {
        Task {
            do {
                let interactor = await WeatherInteractor()
                let weatherData = try await interactor.fetchWeatherData()
                let imageData = try? await fetchBridgeImage()
                let currentWeather = await findCurrentWeather(from: weatherData)
                
                let entry = WeatherEntry(
                    date: Date(),
                    currentWeather: currentWeather,
                    imageData: imageData
                )
                completion(entry)
            } catch {
                completion(placeholder(in: context))
            }
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> ()) {
        Task {
            do {
                let interactor = await WeatherInteractor()
                let weatherData = try await interactor.fetchWeatherData()
                let imageData = try? await fetchBridgeImage()
                let currentWeather = await findCurrentWeather(from: weatherData)
                
                let entry = WeatherEntry(
                    date: Date(),
                    currentWeather: currentWeather,
                    imageData: imageData
                )
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date(timeIntervalSinceNow: 3600))))
            }
        }
    }
    
    private func fetchBridgeImage() async throws -> Data {
        let url = URL(string: "https://raw.githubusercontent.com/danielraffel/ggb/main/ggb.jpg")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
    
    private func findCurrentWeather(from weatherData: [WeatherData]) async -> WeatherData {
        let now = Date()
        return weatherData.min(by: { a, b in
            abs(a.time.timeIntervalSince(now)) < abs(b.time.timeIntervalSince(now))
        }) ?? weatherData[0]
    }
}

struct GGBWatchWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }
    
    private var circularView: some View {
        VStack(spacing: 2) {
            Text("\(entry.currentWeather.temperature, specifier: "%.0f")°")
                .font(.system(size: 16, weight: .bold))
            Text("🌧 \(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
                .font(.system(size: 12))
        }
        .foregroundColor(.white)
    }
    
    private var inlineView: some View {
        Text("\(entry.currentWeather.temperature, specifier: "%.0f")°F 🌧 \(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
    }
    
    private var rectangularView: some View {
        ZStack {
            if let imageData = entry.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(Color.black.opacity(0.4))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.currentWeather.temperature, specifier: "%.1f")°F")
                    .font(.system(size: 20, weight: .bold))
                Text("🌧 \(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
                    .font(.caption2)
                Text("🌬️ \(entry.currentWeather.windSpeed, specifier: "%.1f") mph")
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
        }
    }
}

@main
struct GGBWatchWidget: Widget {
    let kind: String = "GGBWatchWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(watchOS 10.0, *) {
                GGBWatchWidgetEntryView(entry: entry)
                    .containerBackground(.black.gradient, for: .widget)
            } else {
                GGBWatchWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("GGB Weather")
        .description("Current Golden Gate Bridge weather")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}