import Foundation

public struct SharedCachedWeatherData: Codable {
    public let weatherData: [SharedWeatherData]
    public let bridgeImage: Data?
    public let timestamp: Date
    
    public init(weatherData: [SharedWeatherData], bridgeImage: Data?, timestamp: Date) {
        self.weatherData = weatherData
        self.bridgeImage = bridgeImage
        self.timestamp = timestamp
    }
    
    private enum CodingKeys: String, CodingKey {
        case weatherData
        case bridgeImage
        case timestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weatherData = try container.decode([SharedWeatherData].self, forKey: .weatherData)
        bridgeImage = try container.decodeIfPresent(Data.self, forKey: .bridgeImage)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weatherData, forKey: .weatherData)
        try container.encodeIfPresent(bridgeImage, forKey: .bridgeImage)
        try container.encode(timestamp, forKey: .timestamp)
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