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
    case combined(hours: Int, minutes: Int)
    
    var description: String {
        switch self {
        case .combined(let h, let m):
            return "\(h)h \(m)m"
        }
    }
    
    var minutes: Int {
        switch self {
        case .combined(let h, let m):
            return h * 60 + m
        }
    }
    
    var hours: Int {
        switch self {
        case .combined(let h, _):
            return h
        }
    }
    
    var minutesPart: Int {
        switch self {
        case .combined(_, let m):
            return m
        }
    }
    
    static func from(hours: Int, minutes: Int) -> TimeDiff {
        return .combined(hours: hours, minutes: minutes)
    }
} 