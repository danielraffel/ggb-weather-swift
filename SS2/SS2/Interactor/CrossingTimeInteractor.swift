import Foundation

protocol CrossingTimeInteractorProtocol {
    func loadSavedTimeDiffs() -> (first: TimeDiff, second: TimeDiff)
    func saveTimeDiffs(first: TimeDiff, second: TimeDiff)
    func calculateValidCrossingTimes(firstDiff: TimeDiff, secondDiff: TimeDiff) -> (first: CrossingTime, second: CrossingTime)
    func updateFirstCrossing(to date: Date) -> (first: CrossingTime, second: CrossingTime)
    func updateSecondCrossing(to date: Date, relativeTo firstCrossing: CrossingTime) -> CrossingTime
}

final class CrossingTimeInteractor: CrossingTimeInteractorProtocol {
    private let defaults: UserDefaults
    private let firstCrossingKey = "firstCrossingTimeDiff"
    private let secondCrossingKey = "secondCrossingTimeDiff"
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func loadSavedTimeDiffs() -> (first: TimeDiff, second: TimeDiff) {
        // Load saved time diffs from UserDefaults, or use defaults if not found
        if let firstData = defaults.data(forKey: firstCrossingKey),
           let secondData = defaults.data(forKey: secondCrossingKey),
           let first = try? JSONDecoder().decode(TimeDiff.self, from: firstData),
           let second = try? JSONDecoder().decode(TimeDiff.self, from: secondData) {
            return (first: first, second: second)
        }
        return (first: .defaultFirst, second: .defaultSecond)
    }
    
    func saveTimeDiffs(first: TimeDiff, second: TimeDiff) {
        // Save time diffs as encoded data in UserDefaults
        if let firstData = try? JSONEncoder().encode(first),
           let secondData = try? JSONEncoder().encode(second) {
            defaults.set(firstData, forKey: firstCrossingKey)
            defaults.set(secondData, forKey: secondCrossingKey)
        }
    }
    
    func calculateValidCrossingTimes(firstDiff: TimeDiff, secondDiff: TimeDiff) -> (first: CrossingTime, second: CrossingTime) {
        let calendar = Calendar.current
        let now = Date()
        // Truncate to current minute by getting components
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let roundedNow = calendar.date(from: components) ?? now
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: roundedNow) ?? roundedNow
        
        // Calculate first crossing using rounded base time
        let firstDate = firstDiff.applying(to: roundedNow)
        let validFirstDate = clampDate(firstDate, min: roundedNow, max: endOfDay)
        let firstCrossing = CrossingTime(date: validFirstDate, timeDiff: firstDiff)
        
        // Calculate second crossing based on first crossing
        let secondDate = secondDiff.applying(to: validFirstDate)
        let validSecondDate = clampDate(secondDate, min: validFirstDate, max: endOfDay)
        let secondCrossing = CrossingTime(date: validSecondDate, timeDiff: secondDiff)
        
        return (first: firstCrossing, second: secondCrossing)
    }
    
    func updateFirstCrossing(to date: Date) -> (first: CrossingTime, second: CrossingTime) {
        let calendar = Calendar.current
        let now = Date()
        // Truncate to current minute by getting components
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let roundedNow = calendar.date(from: components) ?? now
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        
        // Clamp the first crossing date
        let validFirstDate = clampDate(date, min: roundedNow, max: endOfDay)
        // Calculate time diff from rounded now to preserve exact minutes
        let firstDiff = TimeDiff.from(date: validFirstDate, relativeTo: roundedNow)
        let firstCrossing = CrossingTime(date: validFirstDate, timeDiff: firstDiff)
        
        // Load the saved second crossing diff and recalculate based on new first crossing
        let savedDiffs = loadSavedTimeDiffs()
        var secondDate = savedDiffs.second.applying(to: validFirstDate)
        secondDate = clampDate(secondDate, min: validFirstDate, max: endOfDay)
        let secondDiff = TimeDiff.from(date: secondDate, relativeTo: validFirstDate)
        let secondCrossing = CrossingTime(date: secondDate, timeDiff: secondDiff)
        
        // Save the new time diffs
        saveTimeDiffs(first: firstDiff, second: secondDiff)
        
        return (first: firstCrossing, second: secondCrossing)
    }
    
    func updateSecondCrossing(to date: Date, relativeTo firstCrossing: CrossingTime) -> CrossingTime {
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: firstCrossing.date) ?? firstCrossing.date
        
        // Clamp the second crossing date
        let validSecondDate = clampDate(date, min: firstCrossing.date, max: endOfDay)
        let secondDiff = TimeDiff.from(date: validSecondDate, relativeTo: firstCrossing.date)
        
        // Save the new second crossing diff (keep first crossing diff unchanged)
        let savedDiffs = loadSavedTimeDiffs()
        saveTimeDiffs(first: savedDiffs.first, second: secondDiff)
        
        return CrossingTime(date: validSecondDate, timeDiff: secondDiff)
    }
    
    // Helper function to clamp a date between min and max values
    private func clampDate(_ date: Date, min minDate: Date, max maxDate: Date) -> Date {
        if date < minDate { return minDate }
        if date > maxDate { return maxDate }
        return date
    }
} 