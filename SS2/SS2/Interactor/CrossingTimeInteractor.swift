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
        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        
        // Calculate first crossing
        var firstDate = firstDiff.applying(to: now)
        firstDate = clampDate(firstDate, min: now, max: endOfDay)
        let validFirstDiff = TimeDiff.from(date: firstDate, relativeTo: now)
        let firstCrossing = CrossingTime(date: firstDate, timeDiff: validFirstDiff)
        
        // Calculate second crossing based on first crossing
        var secondDate = secondDiff.applying(to: firstDate)
        secondDate = clampDate(secondDate, min: firstDate, max: endOfDay)
        let validSecondDiff = TimeDiff.from(date: secondDate, relativeTo: firstDate)
        let secondCrossing = CrossingTime(date: secondDate, timeDiff: validSecondDiff)
        
        return (first: firstCrossing, second: secondCrossing)
    }
    
    func updateFirstCrossing(to date: Date) -> (first: CrossingTime, second: CrossingTime) {
        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        
        // Clamp the first crossing date
        let validFirstDate = clampDate(date, min: now, max: endOfDay)
        let firstDiff = TimeDiff.from(date: validFirstDate, relativeTo: now)
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