import Foundation

public struct WeatherData: Identifiable, Codable {
    public let id = UUID()
    public let time: Date
    public let temperature: Double
    public let cloudCover: Double
    public let windSpeed: Double
    public let precipitationProbability: Double
    
    public init(time: Date, temperature: Double, cloudCover: Double, windSpeed: Double, precipitationProbability: Double) {
        self.time = time
        self.temperature = temperature
        self.cloudCover = cloudCover
        self.windSpeed = windSpeed
        self.precipitationProbability = precipitationProbability
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, time, temperature, cloudCover, windSpeed, precipitationProbability
    }
}

public struct CrossingWeather {
    public let temperature: Double
    public let windSpeed: Double
    public let precipitationProbability: Double
    
    public init(temperature: Double, windSpeed: Double, precipitationProbability: Double) {
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.precipitationProbability = precipitationProbability
    }
}

public struct BestVisitTime {
    public let time: Date
    public let temperature: Double
    public let precipitationProbability: Double
    public let cloudCover: Double
    public let windSpeed: Double
    public let score: Double
    
    public init(time: Date, temperature: Double, precipitationProbability: Double, cloudCover: Double, windSpeed: Double, score: Double) {
        self.time = time
        self.temperature = temperature
        self.precipitationProbability = precipitationProbability
        self.cloudCover = cloudCover
        self.windSpeed = windSpeed
        self.score = score
    }
} 