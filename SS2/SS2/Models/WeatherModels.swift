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

enum TimeDiff: Hashable {
    case hours(Int)
    case minutes(Int)
    
    var description: String {
        switch self {
        case .hours(let h):
            return "\(h)h"
        case .minutes(let m):
            return "\(m)m"
        }
    }
    
    var minutes: Int {
        switch self {
        case .hours(let h):
            return h * 60
        case .minutes(let m):
            return m
        }
    }
} 