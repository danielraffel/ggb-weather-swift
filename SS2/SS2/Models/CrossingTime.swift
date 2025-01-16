import Foundation

struct CrossingTime: Equatable {
    let date: Date
    let timeDiff: TimeDiff
    
    var isValid: Bool {
        let calendar = Calendar.current
        let now = Date()
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        return date >= now && date <= endOfDay
    }
    
    static func == (lhs: CrossingTime, rhs: CrossingTime) -> Bool {
        return lhs.date == rhs.date && lhs.timeDiff == rhs.timeDiff
    }
}

enum TimeDiff: Equatable, Codable, Hashable {
    case combined(hours: Int, minutes: Int)
    
    // Default values as per business logic
    static let defaultFirst = TimeDiff.combined(hours: 0, minutes: 0) // "0h0m"
    static let defaultSecond = TimeDiff.combined(hours: 2, minutes: 0) // "2h0m"
    
    var totalMinutes: Int {
        switch self {
        case .combined(let h, let m):
            return h * 60 + m
        }
    }
    
    var displayString: String {
        switch self {
        case .combined(let h, let m):
            if h == 0 && m == 0 { return "0h0m" }
            if h == 0 { return "\(m)m" }
            if m == 0 { return "\(h)h" }
            return "\(h)h\(m)m"
        }
    }
    
    var description: String {
        switch self {
        case .combined(let h, let m):
            return "\(h)h \(m)m"
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
    
    static func from(date: Date, relativeTo baseDate: Date) -> TimeDiff {
        let diff = Calendar.current.dateComponents([.hour, .minute], from: baseDate, to: date)
        return .combined(hours: diff.hour ?? 0, minutes: diff.minute ?? 0)
    }
    
    static func from(hours: Int, minutes: Int) -> TimeDiff {
        return .combined(hours: hours, minutes: minutes)
    }
    
    func applying(to date: Date) -> Date {
        return Calendar.current.date(byAdding: .minute, value: totalMinutes, to: date) ?? date
    }
    
    // Parse a time diff string like "1h30m" or "45m"
    static func parse(_ string: String) -> TimeDiff {
        let pattern = #"^(?:(\d+)h)?(?:(\d+)m)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) else {
            return .defaultFirst
        }
        
        let hours = match.range(at: 1).location != NSNotFound ? 
            Int(String(string[Range(match.range(at: 1), in: string)!])) ?? 0 : 0
        let minutes = match.range(at: 2).location != NSNotFound ? 
            Int(String(string[Range(match.range(at: 2), in: string)!])) ?? 0 : 0
        
        return .combined(hours: hours, minutes: minutes)
    }
} 