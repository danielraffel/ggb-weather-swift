import Foundation
import os

@globalActor actor WeatherActor {
    static let shared = WeatherActor()
}

public protocol WeatherInteracting {
    func fetchWeatherData() async throws -> [SharedWeatherData]
    func fetchSunsetTime() async throws -> Date
    func fetchAndCacheWeatherData() async throws -> [SharedWeatherData]
}

public final class WeatherInteractor: WeatherInteracting {
    private let weatherURL = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=37.8199&longitude=-122.4783&hourly=temperature_2m,precipitation_probability,cloud_cover,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America%2FLos_Angeles")!
    private let sunsetURL = URL(string: "https://api.sunrise-sunset.org/json?lat=37.8199&lng=-122.4783&formatted=0")!
    private let sharedDataInteractor: SharedDataInteracting
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "WeatherInteractor")
    
    public init(sharedDataInteractor: SharedDataInteracting = SharedDataInteractor()) {
        self.sharedDataInteractor = sharedDataInteractor
    }
    
    public func fetchWeatherData() async throws -> [SharedWeatherData] {
        return try await fetchAndCacheWeatherData()
    }
    
    public func fetchAndCacheWeatherData() async throws -> [SharedWeatherData] {
        let weatherData = try await fetchWeatherFromAPI()
        
        // Cache the weather data
        let cachedData = SharedCachedWeatherData(
            weatherData: weatherData,
            bridgeImage: nil,
            timestamp: Date()
        )
        try await sharedDataInteractor.saveWeatherData(cachedData)
        return weatherData
    }
    
    private func fetchWeatherFromAPI() async throws -> [SharedWeatherData] {
        let (data, _) = try await URLSession.shared.data(from: weatherURL)
        
        // Debug: Print raw response
        if let jsonStr = String(data: data, encoding: .utf8) {
            logger.notice("📥 Raw API Response: \(jsonStr)")
        }
        
        let decoder = JSONDecoder()
        
        // Create a date formatter
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        decoder.dateDecodingStrategy = .formatted(formatter)
        
        do {
            let response = try decoder.decode(WeatherResponse.self, from: data)
            return zip(response.hourly.time,
                      zip(response.hourly.temperature,
                          zip(response.hourly.cloudCover,
                              zip(response.hourly.windSpeed,
                                  response.hourly.precipitationProbability))))
                .map { time, data in
                    let (temp, (cloud, (wind, precip))) = data
                    return SharedWeatherData(
                        time: time,
                        temperature: temp,
                        cloudCover: cloud,
                        windSpeed: wind,
                        precipitationProbability: precip
                    )
                }
        } catch {
            logger.error("❌ Failed to decode weather response: \(error)")
            throw error
        }
    }
    
    public func fetchSunsetTime() async throws -> Date {
        let (data, _) = try await URLSession.shared.data(from: sunsetURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let response = try decoder.decode(SunsetResponse.self, from: data)
        return response.results.sunset
    }
}

private struct WeatherResponse: Codable {
    let hourly: HourlyData
    
    struct HourlyData: Codable {
        let time: [Date]
        let temperature: [Double]
        let cloudCover: [Double]
        let windSpeed: [Double]
        let precipitationProbability: [Double]
        
        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case cloudCover = "cloud_cover"
            case windSpeed = "wind_speed_10m"
            case precipitationProbability = "precipitation_probability"
        }
    }
}

private struct SunsetResponse: Codable {
    let results: SunsetResults
    
    struct SunsetResults: Codable {
        let sunset: Date
    }
} 