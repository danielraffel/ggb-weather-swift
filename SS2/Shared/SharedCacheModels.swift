import Foundation

public struct CachedWeatherData: Codable {
    public let weatherData: [WeatherData]
    public let timestamp: Date
    public let bridgeImage: Data?
    
    public init(weatherData: [WeatherData], timestamp: Date = Date(), bridgeImage: Data? = nil) {
        self.weatherData = weatherData
        self.timestamp = timestamp
        self.bridgeImage = bridgeImage
    }
    
    private enum CodingKeys: String, CodingKey {
        case weatherData
        case timestamp
        case bridgeImage
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weatherData = try container.decode([WeatherData].self, forKey: .weatherData)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        bridgeImage = try container.decodeIfPresent(Data.self, forKey: .bridgeImage)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weatherData, forKey: .weatherData)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(bridgeImage, forKey: .bridgeImage)
    }
}

public enum SharedDataError: LocalizedError {
    case saveFailed
    case loadFailed
    case cacheEmpty
    case cacheStale
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Unable to save weather data"
        case .loadFailed:
            return "Unable to load weather data"
        case .cacheEmpty:
            return "Open iPhone app to load weather"
        case .cacheStale:
            return "Weather data needs refresh"
        case .invalidData:
            return "Invalid weather data"
        }
    }
}

@globalActor public actor SharedDataActor {
    public static let shared = SharedDataActor()
    private init() {}
} 