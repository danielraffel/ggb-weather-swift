import Foundation

class WeatherInteractor {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter
    }()
    
    func fetchWeatherData() async throws -> [WeatherData] {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=37.8199&longitude=-122.4783&hourly=temperature_2m,cloudcover,windspeed_10m,precipitation_probability&timezone=America/Los_Angeles&forecast_days=1&temperature_unit=fahrenheit"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = self.dateFormatter.date(from: dateString) {
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
                windSpeed: hourly.windspeed10m[index] * 0.621371, // Convert to mph
                precipitationProbability: hourly.precipitationProbability[index]
            )
        }
    }
}

private struct WeatherResponse: Codable {
    let hourly: HourlyData
    
    struct HourlyData: Codable {
        let time: [Date]
        let temperature2m: [Double]
        let precipitationProbability: [Double]
        let cloudcover: [Double]
        let windspeed10m: [Double]
        
        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case cloudcover
            case windspeed10m = "windspeed_10m"
        }
    }
} 