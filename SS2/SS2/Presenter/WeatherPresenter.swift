import Foundation
import SwiftUI

@MainActor
class WeatherPresenter: ObservableObject {
    private let interactor: WeatherInteractorProtocol
    private let defaults = UserDefaults.standard
    private let firstCrossingTimeDiffKey = "firstCrossingTimeDiff"
    private let secondCrossingTimeDiffKey = "secondCrossingTimeDiff"
    
    @Published var weatherData: [WeatherData] = []
    @Published var sunsetTime: String?
    @Published var firstCrossingTimeDiff: TimeDiff = .combined(hours: 0, minutes: 0)
    @Published var secondCrossingTimeDiff: TimeDiff = .combined(hours: 2, minutes: 0)
    @Published var firstCrossingTime: Date = Date()
    @Published var secondCrossingTime: Date = Date().addingTimeInterval(2 * 3600)
    @Published var firstCrossingWeather: CrossingWeather?
    @Published var secondCrossingWeather: CrossingWeather?
    @Published var bestVisitTimes: [BestVisitTime] = []
    @Published var isRefreshing = false
    
    private var isLoading = false
    
    init(interactor: WeatherInteractorProtocol) {
        self.interactor = interactor
        print("Current UserDefaults for second crossing - hours: \(defaults.value(forKey: "\(secondCrossingTimeDiffKey)_hours") as? Int ?? -1), minutes: \(defaults.value(forKey: "\(secondCrossingTimeDiffKey)_minutes") as? Int ?? -1)")
        loadSavedTimeDiffs()
    }
    
    func loadData() {
        Task {
            await fetchWeatherData()
            await fetchSunsetTime()
            calculateBestVisitTimes()
            updateCrossingWeather()
        }
    }
    
    func updateCrossingWeather() {
        // Update first crossing time based on time diff
        let now = Date()
        let firstMinutes = firstCrossingTimeDiff.minutes
        firstCrossingTime = Calendar.current.date(byAdding: .minute, value: firstMinutes, to: now) ?? now
        
        // Update second crossing time based on first crossing time and time diff
        let secondMinutes = secondCrossingTimeDiff.minutes
        secondCrossingTime = Calendar.current.date(byAdding: .minute, value: secondMinutes, to: now) ?? firstCrossingTime
        
        // Update weather for both crossings
        firstCrossingWeather = getWeatherForTime(firstCrossingTime)
        secondCrossingWeather = getWeatherForTime(secondCrossingTime)
    }
    
    private func fetchWeatherData() async {
        do {
            weatherData = try await interactor.fetchWeatherData()
        } catch {
            print("Error fetching weather data: \(error)")
        }
    }
    
    private func fetchSunsetTime() async {
        do {
            let sunset = try await interactor.fetchSunsetTime()
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            sunsetTime = formatter.string(from: sunset)
        } catch {
            print("Error fetching sunset time: \(error)")
        }
    }
    
    private func calculateBestVisitTimes() {
        let filteredData = weatherData.filter { data in
            let hour = Calendar.current.component(.hour, from: data.time)
            return hour >= 6 && hour <= 20
        }
        
        let scoredTimes = filteredData.map { data in
            let tempScore = data.temperature * 2
            let rainScore = 100 - data.precipitationProbability
            let cloudScore = (100 - data.cloudCover) / 2
            let windScore = (20 - data.windSpeed) / 2
            
            return BestVisitTime(
                time: data.time,
                temperature: data.temperature,
                precipitationProbability: data.precipitationProbability,
                cloudCover: data.cloudCover,
                windSpeed: data.windSpeed,
                score: tempScore + rainScore + cloudScore + windScore
            )
        }.sorted { $0.score > $1.score }
        
        bestVisitTimes = Array(scoredTimes.prefix(2))
    }
    
    private func getWeatherForTime(_ time: Date) -> CrossingWeather? {
        guard let weatherAtTime = weatherData.first(where: { data in
            let calendar = Calendar.current
            return calendar.compare(data.time, to: time, toGranularity: .hour) == .orderedSame
        }) else { return nil }
        
        return CrossingWeather(
            temperature: weatherAtTime.temperature,
            windSpeed: weatherAtTime.windSpeed,
            precipitationProbability: weatherAtTime.precipitationProbability
        )
    }
    
    func refresh() async {
        isRefreshing = true
        await fetchWeatherData()
        await fetchSunsetTime()
        calculateBestVisitTimes()
        updateCrossingWeather()
        isRefreshing = false
    }
    
    func saveTimeDiffs() {
        if isLoading { return }
        
        print("DEBUG: Saving time diffs")
        defaults.set(firstCrossingTimeDiff.hours, forKey: "\(firstCrossingTimeDiffKey)_hours")
        defaults.set(firstCrossingTimeDiff.minutesPart, forKey: "\(firstCrossingTimeDiffKey)_minutes")
        defaults.set(secondCrossingTimeDiff.hours, forKey: "\(secondCrossingTimeDiffKey)_hours")
        defaults.set(secondCrossingTimeDiff.minutesPart, forKey: "\(secondCrossingTimeDiffKey)_minutes")
        defaults.synchronize()
        
        NSLog("Saved crossings - first: \(firstCrossingTimeDiff.hours)h \(firstCrossingTimeDiff.minutesPart)m, second: \(secondCrossingTimeDiff.hours)h \(secondCrossingTimeDiff.minutesPart)m")
    }
    
    func loadSavedTimeDiffs() {
        isLoading = true
        if let firstHours = defaults.object(forKey: "\(firstCrossingTimeDiffKey)_hours") as? Int,
           let firstMinutes = defaults.object(forKey: "\(firstCrossingTimeDiffKey)_minutes") as? Int {
            firstCrossingTimeDiff = .combined(hours: firstHours, minutes: firstMinutes)
        }
        
        if let secondHours = defaults.object(forKey: "\(secondCrossingTimeDiffKey)_hours") as? Int,
           let secondMinutes = defaults.object(forKey: "\(secondCrossingTimeDiffKey)_minutes") as? Int {
            secondCrossingTimeDiff = .combined(hours: secondHours, minutes: secondMinutes)
        }
        isLoading = false
        updateCrossingWeather()
    }
} 