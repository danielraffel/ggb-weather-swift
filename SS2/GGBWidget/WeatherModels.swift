import Foundation

struct WeatherData: Identifiable {
    let id = UUID()
    let time: Date
    let temperature: Double
    let cloudCover: Double
    let windSpeed: Double
    let precipitationProbability: Double
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