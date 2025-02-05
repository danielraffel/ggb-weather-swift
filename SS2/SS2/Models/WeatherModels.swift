import Foundation

struct WeatherData: Identifiable, Codable {
    let id = UUID()
    let time: Date
    let temperature: Double
    let cloudCover: Double
    let windSpeed: Double
    let precipitationProbability: Double
    
    init(time: Date, temperature: Double, cloudCover: Double, windSpeed: Double, precipitationProbability: Double) {
        self.time = time
        self.temperature = temperature
        self.cloudCover = cloudCover
        self.windSpeed = windSpeed
        self.precipitationProbability = precipitationProbability
    }
}

struct CrossingWeather {
    let temperature: Double
    let windSpeed: Double
    let precipitationProbability: Double
}

struct BestVisitTime {
    let time: Date
    let temperature: Double
    let precipitationProbability: Double
    let cloudCover: Double
    let windSpeed: Double
    let score: Double
} 