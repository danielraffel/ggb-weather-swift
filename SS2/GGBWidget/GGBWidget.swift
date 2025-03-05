//
//  GGBWidget.swift
//  GGBWidget
//
//  Created by Daniel Raffel on 1/31/25.
//

import WidgetKit
import SwiftUI
import os
import Shared

private let logger = Logger(subsystem: "com.danielraffel.ggbweather", category: "GGBWidget")

struct Provider: TimelineProvider {
    private let sharedDataInteractor = SharedDataInteractor()
    private let crossingTimeInteractor: Shared.CrossingTimeInteractor
    
    init() {
        // Use the shared app group UserDefaults
        let defaults = UserDefaults(suiteName: "group.com.danielraffel.ggbweather") ?? .standard
        self.crossingTimeInteractor = Shared.CrossingTimeInteractor(defaults: defaults)
    }
    
    func placeholder(in context: Context) -> WeatherEntry {
        logger.debug("⚡️ Providing placeholder entry")
        let placeholderWeather = WeatherData(
            time: Date(),
            temperature: 68.0,
            cloudCover: 20.0,
            windSpeed: 8.0,
            precipitationProbability: 10.0
        )
        
        let placeholderCrossing = CrossingWeather(
            temperature: 65.0,
            windSpeed: 8.0,
            precipitationProbability: 10.0
        )
        
        // For the current weather only layout
        if context.family == .systemMedium && context.isPreview {
            let emptyBestTime = BestVisitTime(
                time: createDate(from: "2:00 PM"),
                temperature: 72.0,
                precipitationProbability: 5.0,
                cloudCover: 15.0,
                windSpeed: 6.0,
                score: 0  // Set score to 0 to show current weather only layout
            )
            
            // Load placeholder image from bundle
            let imageName = "placeholder_bridge"
            if let image = UIImage(named: imageName),
               let imageData = image.jpegData(compressionQuality: 0.5) {
                logger.debug("✅ Created placeholder with image")
                return WeatherEntry(
                    date: Date(),
                    currentWeather: placeholderWeather,
                    bestTime: emptyBestTime,
                    secondBestTime: emptyBestTime,
                    firstCrossing: placeholderCrossing,
                    secondCrossing: placeholderCrossing,
                    firstCrossingTime: nil,
                    secondCrossingTime: nil,
                    imageData: imageData
                )
            }
        }
        
        // For the full layout with best times
        let bestPlaceholderTime = BestVisitTime(
            time: createDate(from: "2:00 PM"),
            temperature: 72.0,
            precipitationProbability: 5.0,
            cloudCover: 15.0,
            windSpeed: 6.0,
            score: 85
        )
        
        let secondBestPlaceholderTime = BestVisitTime(
            time: createDate(from: "3:00 PM"),
            temperature: 70.0,
            precipitationProbability: 8.0,
            cloudCover: 25.0,
            windSpeed: 7.0,
            score: 80
        )
        
        // Load placeholder image from bundle
        let imageName = "placeholder_bridge"
        if let image = UIImage(named: imageName),
           let imageData = image.jpegData(compressionQuality: 0.5) {
            logger.debug("✅ Created placeholder with image")
            return WeatherEntry(
                date: Date(),
                currentWeather: placeholderWeather,
                bestTime: bestPlaceholderTime,
                secondBestTime: secondBestPlaceholderTime,
                firstCrossing: placeholderCrossing,
                secondCrossing: placeholderCrossing,
                firstCrossingTime: nil,
                secondCrossingTime: nil,
                imageData: imageData
            )
        }
        
        logger.debug("⚠️ Created placeholder without image")
        return WeatherEntry(
            date: Date(),
            currentWeather: placeholderWeather,
            bestTime: bestPlaceholderTime,
            secondBestTime: secondBestPlaceholderTime,
            firstCrossing: placeholderCrossing,
            secondCrossing: placeholderCrossing,
            firstCrossingTime: nil,
            secondCrossingTime: nil,
            imageData: nil
        )
    }
    
    private func createDate(from timeString: String) -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mm a"
        dateFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return dateFormatter.date(from: timeString) ?? Date()
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> ()) {
        logger.debug("📸 Getting snapshot")
        Task {
            if context.isPreview {
                logger.debug("📸 Providing preview snapshot")
                completion(placeholder(in: context))
                return
            }
            
            do {
                if let cachedData = try await sharedDataInteractor.loadWeatherData(maxRetries: 2, retryDelay: 1.0) {
                    logger.debug("📸 Using cached data for snapshot")
                    let (firstDiff, secondDiff) = crossingTimeInteractor.loadSavedTimeDiffs()
                    let crossings = crossingTimeInteractor.calculateValidCrossingTimes(firstDiff: firstDiff, secondDiff: secondDiff)
                    let entry = createEntry(from: cachedData, firstCrossingTime: crossings.first.date, secondCrossingTime: crossings.second.date)
                    completion(entry)
                    return
                }
                
                logger.debug("📸 Falling back to placeholder for snapshot")
                completion(placeholder(in: context))
            } catch {
                logger.error("❌ Snapshot error: \(error.localizedDescription)")
                completion(placeholder(in: context))
            }
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> ()) {
        logger.debug("⏰ Getting timeline")
        Task {
            do {
                // Calculate current crossing times
                let (firstDiff, secondDiff) = crossingTimeInteractor.loadSavedTimeDiffs()
                var crossings = crossingTimeInteractor.calculateValidCrossingTimes(firstDiff: firstDiff, secondDiff: secondDiff)
                
                // Check if first crossing is in the past and recalculate if needed
                let now = Date()
                if crossings.first.date < now {
                    logger.debug("🔄 First crossing is in past, recalculating times")
                    let newCrossings = crossingTimeInteractor.calculateValidCrossingTimes(firstDiff: firstDiff, secondDiff: secondDiff)
                    logger.debug("🕒 Updated first crossing to \(newCrossings.first.date), second to \(newCrossings.second.date)")
                    crossings = newCrossings
                }
                
                // Try to load cached data first
                if let cachedData = try await sharedDataInteractor.loadWeatherData(maxRetries: 3, retryDelay: 2.0) {
                    logger.debug("✅ Using cached data for timeline")
                    let entry = createEntry(from: cachedData, firstCrossingTime: crossings.first.date, secondCrossingTime: crossings.second.date)
                    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
                    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
                    return
                }
                
                // Fallback to network if no cache
                logger.debug("🌐 Fetching fresh data for timeline")
                let interactor = await WeatherInteractor()
                let weatherData = try await interactor.fetchWeatherData()
                let imageData = try? await fetchBridgeImage()
                
                let entry = WeatherEntry(
                    date: Date(),
                    currentWeather: findCurrentWeather(from: weatherData),
                    bestTime: calculateBestTimes(from: weatherData)[0],
                    secondBestTime: calculateBestTimes(from: weatherData)[1],
                    firstCrossing: getWeatherForTime(crossings.first.date, from: weatherData),
                    secondCrossing: getWeatherForTime(crossings.second.date, from: weatherData),
                    firstCrossingTime: crossings.first.date,
                    secondCrossingTime: crossings.second.date,
                    imageData: imageData
                )
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
                completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
                
                // Force widget to reload after getting new data
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                logger.error("❌ Timeline error: \(error.localizedDescription)")
                completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date(timeIntervalSinceNow: 900))))
            }
        }
    }
    
    private func createEntry(from cachedData: CachedWeatherData, firstCrossingTime: Date, secondCrossingTime: Date) -> WeatherEntry {
        // Only take what we need - last 24 hours of data
        let recentData = Array(cachedData.weatherData)  // Use all data, don't limit to last 24 hours
        let bestTimes = calculateBestTimes(from: recentData)
        
        // Find weather for crossing times
        let firstCrossingWeather = getWeatherForTime(firstCrossingTime, from: recentData)
        let secondCrossingWeather = getWeatherForTime(secondCrossingTime, from: recentData)
        
        logger.debug("🕒 Creating entry with crossings at \(formatTime(firstCrossingTime)) and \(formatTime(secondCrossingTime))")
        if let first = firstCrossingWeather {
            logger.debug("First crossing weather: \(first.temperature)°F, \(first.windSpeed)mph")
        }
        if let second = secondCrossingWeather {
            logger.debug("Second crossing weather: \(second.temperature)°F, \(second.windSpeed)mph")
        }
        
        return WeatherEntry(
            date: Date(),
            currentWeather: findCurrentWeather(from: recentData),
            bestTime: bestTimes[0],
            secondBestTime: bestTimes[1],
            firstCrossing: firstCrossingWeather,
            secondCrossing: secondCrossingWeather,
            firstCrossingTime: firstCrossingTime,
            secondCrossingTime: secondCrossingTime,
            imageData: cachedData.bridgeImage
        )
    }
    
    private func fetchBridgeImage() async throws -> Data {
        logger.debug("🌉 Fetching bridge image")
        // First try to get cached image
        if let cachedData = try? await sharedDataInteractor.loadWeatherData(maxRetries: 2, retryDelay: 1.0),
           let cachedImage = cachedData.bridgeImage {
            logger.debug("✅ Using cached bridge image")
            return cachedImage
        }
        
        // If no cached image, fetch and compress
        logger.debug("🌐 Downloading bridge image")
        let url = URL(string: "https://raw.githubusercontent.com/danielraffel/ggb/main/ggb.screenshot.png")!
        let (data, _) = try await URLSession.shared.data(from: url)
        if let image = UIImage(data: data),
           let compressedData = image.jpegData(compressionQuality: 0.5) {
            logger.debug("✅ Compressed bridge image")
            return compressedData
        }
        return data
    }
    
    private func calculateBestTimes(from weatherData: [WeatherData]) -> [BestVisitTime] {
        let now = Date()
        let twelveHoursFromNow = Calendar.current.date(byAdding: .hour, value: 12, to: now) ?? now
        
        let filteredData = weatherData.filter { data in
            let hour = Calendar.current.component(.hour, from: data.time)
            return hour >= 6 && hour <= 20 && data.time <= twelveHoursFromNow
        }
        
        // Limit to top 5 scores before sorting
        return Array(filteredData.map { data in
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
        }.sorted { $0.score > $1.score }.prefix(5))
    }
    
    private func findCurrentWeather(from weatherData: [WeatherData]) -> WeatherData {
        let now = Date()
        let calendar = Calendar.current
        
        // First try to find exact hour match
        if let exactMatch = weatherData.first(where: { data in
            calendar.compare(data.time, to: now, toGranularity: .hour) == .orderedSame
        }) {
            return exactMatch
        }
        
        // If no exact match, find closest time
        return weatherData.min(by: { a, b in
            abs(a.time.timeIntervalSince(now)) < abs(b.time.timeIntervalSince(now))
        }) ?? weatherData[0]
    }
    
    private func getWeatherForTime(_ time: Date, from weatherData: [WeatherData]) -> CrossingWeather? {
        // Find the closest weather data point within 30 minutes of the target time
        let closestData = weatherData.min(by: { a, b in
            abs(a.time.timeIntervalSince(time)) < abs(b.time.timeIntervalSince(time))
        })
        
        guard let weatherAtTime = closestData else {
            logger.error("❌ No weather data found for time: \(time)")
            return nil
        }
        
        // Log the time difference for debugging
        let timeDiff = abs(weatherAtTime.time.timeIntervalSince(time)) / 60 // Convert to minutes
        logger.debug("✅ Found weather for \(formatTime(time)): temp=\(weatherAtTime.temperature)°F, wind=\(weatherAtTime.windSpeed)mph (time diff: \(Int(timeDiff)) minutes)")
        
        return CrossingWeather(
            temperature: weatherAtTime.temperature,
            windSpeed: weatherAtTime.windSpeed,
            precipitationProbability: weatherAtTime.precipitationProbability
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter.string(from: date)
    }
}

struct WeatherEntry: TimelineEntry {
    let date: Date
    let currentWeather: WeatherData
    let bestTime: BestVisitTime
    let secondBestTime: BestVisitTime
    let firstCrossing: CrossingWeather?
    let secondCrossing: CrossingWeather?
    let firstCrossingTime: Date?
    let secondCrossingTime: Date?
    let imageData: Data?
}

struct GGBWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            if entry.bestTime.score > 0 {
                mediumWidget
            } else {
                mediumCurrentWeatherWidget
            }
        default:
            mediumWidget
        }
    }
    
    private var smallWidget: some View {
        VStack {
            Spacer() // Push content down
            
            VStack(spacing: 2) {
                Text("Current Weather")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 2) {
                    Text("🌡️\(entry.currentWeather.temperature, specifier: "%.0f")°F")
                        .font(.system(size: 10))
                    Text("💨\(entry.currentWeather.windSpeed, specifier: "%.0f") mph")
                        .font(.system(size: 10))
                    Text("🌧\(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.bottom, 4) // Minimal padding at the bottom
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            if let imageData = entry.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: -20, y: -20)
                    .padding(.bottom, -20)
                    .padding(.horizontal, -20)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                .clear,
                                .black.opacity(0.4)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                Color.black.opacity(0.8)
            }
        }
    }
    
    private var mediumWidget: some View {
        VStack(spacing: 8) {
            // Current Weather (Top)
            VStack(spacing: 2) {
                Text("Current Weather")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 12) {
                    Text("🌡️ \(entry.currentWeather.temperature, specifier: "%.1f")°F")
                        .font(.caption)
                    Text("💨 \(entry.currentWeather.windSpeed, specifier: "%.1f") mph")
                        .font(.caption)
                    Text("🌧 \(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            
            // Best Times (Bottom)
            HStack(spacing: 0) {
                // Best Time (Left)
                VStack(alignment: .leading, spacing: 4) {
                    Text("🥇 Best Time")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .bold()
                    
                    Text(formatTime(entry.bestTime.time))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(entry.bestTime.temperature, specifier: "🌡️ %.1f")°F")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("\(entry.bestTime.windSpeed, specifier: "💨 %.1f") mph")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("\(entry.bestTime.precipitationProbability, specifier: "🌧️ %.0f")%")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Second Best Time (Right)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Second Best 🥈")
                        .font(.caption)
                        .foregroundColor(.white)
                        .bold()
                    
                    Text(formatTime(entry.secondBestTime.time))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(entry.secondBestTime.temperature, specifier: "%.1f")°F 🌡️")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("\(entry.secondBestTime.windSpeed, specifier: "%.1f") mph 💨")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("\(entry.secondBestTime.precipitationProbability, specifier: "%.0f")% 🌧️")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
    
    private var mediumCurrentWeatherWidget: some View {
        VStack {
            Spacer()
            
            // Current Weather (Bottom)
            VStack(spacing: 2) {
                Text("Current Weather")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 12) {
                    Text("🌡️ \(entry.currentWeather.temperature, specifier: "%.1f")°F")
                        .font(.caption)
                    Text("💨 \(entry.currentWeather.windSpeed, specifier: "%.1f") mph")
                        .font(.caption)
                    Text("🌧 \(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 4) // Minimal padding at the bottom
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            if let imageData = entry.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .padding(.horizontal, -20)
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                .clear,
                                .black.opacity(0.4)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter.string(from: date)
    }
}

@main
struct GGBWidget: WidgetBundle {
    var body: some Widget {
        SmallWeatherWidget()
        MediumCrossingTimesWidget()
        MediumBestTimesWidget()
        MediumCurrentWeatherWidget()
        SmallBridgeWidget()
        MediumBridgeWidget()
    }
}

// Small Widget
struct SmallWeatherWidget: Widget {
    let kind: String = "SmallWeatherWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            GGBWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Weather")
        .description("Shows current weather at the bridge")
        .supportedFamilies([.systemSmall])
    }
}

// Medium Widget with Best Times
struct MediumBestTimesWidget: Widget {
    let kind: String = "MediumBestTimesWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            mediumWidget(entry: entry)
        }
        .configurationDisplayName("Best Times")
        .description("Shows best times to visit and current weather")
        .supportedFamilies([.systemMedium])
    }
}

// Medium Widget with Current Weather Only
struct MediumCurrentWeatherWidget: Widget {
    let kind: String = "MediumCurrentWeatherWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            mediumCurrentWeatherWidget(entry: entry)
        }
        .configurationDisplayName("Current Weather (Large)")
        .description("Shows current weather in a larger format")
        .supportedFamilies([.systemMedium])
    }
}

// Small Bridge Widget (Image Only)
struct SmallBridgeWidget: Widget {
    let kind: String = "SmallBridgeWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            smallBridgeWidget(entry: entry)
        }
        .configurationDisplayName("Bridge View (Small)")
        .description("Shows just the bridge image")
        .supportedFamilies([.systemSmall])
    }
}

// Medium Bridge Widget (Image Only)
struct MediumBridgeWidget: Widget {
    let kind: String = "MediumBridgeWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            mediumBridgeWidget(entry: entry)
        }
        .configurationDisplayName("Bridge View (Medium)")
        .description("Shows just the bridge image in a larger format")
        .supportedFamilies([.systemMedium])
    }
}

// Medium Widget with Crossing Times
struct MediumCrossingTimesWidget: Widget {
    let kind: String = "MediumCrossingTimesWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            mediumCrossingTimesWidget(entry: entry)
        }
        .configurationDisplayName("Crossing Times")
        .description("Shows weather for your planned crossings")
        .supportedFamilies([.systemMedium])
    }
}

// Move the view builders to top level for reuse
private func mediumWidget(entry: Provider.Entry) -> some View {
    VStack(spacing: 8) {
        // Current Weather (Top)
        VStack(spacing: 2) {
            Text("Current Weather")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                Text("🌡️ \(entry.currentWeather.temperature, specifier: "%.1f")°F")
                    .font(.caption)
                Text("💨 \(entry.currentWeather.windSpeed, specifier: "%.1f") mph")
                    .font(.caption)
                Text("🌧 \(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
                    .font(.caption)
            }
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        
        // Best Times (Bottom)
        HStack(spacing: 0) {
            // Best Time (Left)
            VStack(alignment: .leading, spacing: 4) {
                Text("🥇 Best Time")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .bold()
                
                Text(formatTime(entry.bestTime.time))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(entry.bestTime.temperature, specifier: "🌡️ %.1f")°F")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text("\(entry.bestTime.windSpeed, specifier: "💨 %.1f") mph")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text("\(entry.bestTime.precipitationProbability, specifier: "🌧️ %.0f")%")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Second Best Time (Right)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Second Best 🥈")
                    .font(.caption)
                    .foregroundColor(.white)
                    .bold()
                
                Text(formatTime(entry.secondBestTime.time))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(entry.secondBestTime.temperature, specifier: "%.1f")°F 🌡️")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text("\(entry.secondBestTime.windSpeed, specifier: "%.1f") mph 💨")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text("\(entry.secondBestTime.precipitationProbability, specifier: "%.0f")% 🌧️")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
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

private func mediumCurrentWeatherWidget(entry: Provider.Entry) -> some View {
    VStack {
        Spacer()
        
        // Current Weather (Bottom)
        VStack(spacing: 2) {
            Text("Current Weather")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                Text("🌡️ \(entry.currentWeather.temperature, specifier: "%.1f")°F")
                    .font(.caption)
                Text("💨 \(entry.currentWeather.windSpeed, specifier: "%.1f") mph")
                    .font(.caption)
                Text("🌧 \(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
                    .font(.caption)
            }
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 4) // Minimal padding at the bottom
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .containerBackground(for: .widget) {
        if let imageData = entry.imageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .padding(.horizontal, -20)
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .clear,
                            .black.opacity(0.4)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
    return formatter.string(from: date)
}

// View builders for the bridge-only widgets
private func smallBridgeWidget(entry: Provider.Entry) -> some View {
    Color.clear
        .containerBackground(for: .widget) {
            if let imageData = entry.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: -20, y: -20)
                    .padding(.bottom, -20)
                    .padding(.horizontal, -20)
                    .clipped()
            }
        }
}

private func mediumBridgeWidget(entry: Provider.Entry) -> some View {
    Color.clear
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

// Add this view builder at the bottom of the file
private func mediumCrossingTimesWidget(entry: Provider.Entry) -> some View {
    VStack(spacing: 8) {
        // Current Weather (Top)
        VStack(spacing: 2) {
            Text("Current Weather")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                Text("🌡️ \(entry.currentWeather.temperature, specifier: "%.1f")°F")
                Text("💨 \(entry.currentWeather.windSpeed, specifier: "%.1f") mph")
                Text("🌧 \(entry.currentWeather.precipitationProbability, specifier: "%.0f")%")
            }
            .font(.caption)
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        
        // Crossing Times (Bottom)
        HStack(spacing: 0) {
            // First Crossing (Left)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sunrise.fill")
                        .foregroundColor(.yellow)
                    Text("First Crossing")
                        .font(.caption)
                        .foregroundColor(.white)
                        .bold()
                }
                
                if let firstCrossing = entry.firstCrossing,
                   let firstTime = entry.firstCrossingTime {
                    Text(formatTime(firstTime))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(firstCrossing.temperature, specifier: "🌡️ %.1f")°F")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("\(firstCrossing.windSpeed, specifier: "💨 %.1f") mph")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("\(firstCrossing.precipitationProbability, specifier: "🌧️ %.0f")%")
                        .font(.caption)
                        .foregroundColor(.white)
                } else {
                    Text("No Data")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Second Crossing (Right)
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Text("Second Crossing")
                        .font(.caption)
                        .foregroundColor(.white)
                        .bold()
                    Image(systemName: "sunset.fill")
                        .foregroundColor(.orange)
                }
                
                if let secondCrossing = entry.secondCrossing,
                   let secondTime = entry.secondCrossingTime {
                    Text(formatTime(secondTime))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(secondCrossing.temperature, specifier: "%.1f")°F 🌡️")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("\(secondCrossing.windSpeed, specifier: "%.1f") mph 💨")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Text("\(secondCrossing.precipitationProbability, specifier: "%.0f")% 🌧️")
                        .font(.caption)
                        .foregroundColor(.white)
                } else {
                    Text("No Data")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
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
