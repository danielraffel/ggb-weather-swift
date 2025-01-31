import Foundation
import SwiftUI

@MainActor
class WeatherPresenter: ObservableObject {
    private let interactor: WeatherInteractorProtocol
    private let crossingTimeInteractor: CrossingTimeInteractorProtocol
    
    @Published var weatherData: [WeatherData] = []
    @Published var sunsetTime: String?
    @Published var firstCrossing: CrossingTime
    @Published var secondCrossing: CrossingTime
    @Published var firstCrossingWeather: CrossingWeather?
    @Published var secondCrossingWeather: CrossingWeather?
    @Published var bestVisitTimes: [BestVisitTime] = []
    @Published var isRefreshing = false
    @Published var isRestoringFromBackground = false
    
    private var timer: Timer?
    
    init(interactor: WeatherInteractorProtocol, crossingTimeInteractor: CrossingTimeInteractorProtocol) {
        self.interactor = interactor
        self.crossingTimeInteractor = crossingTimeInteractor
        
        // Initialize with default crossing times
        let (firstDiff, secondDiff) = crossingTimeInteractor.loadSavedTimeDiffs()
        let crossings = crossingTimeInteractor.calculateValidCrossingTimes(firstDiff: firstDiff, secondDiff: secondDiff)
        self.firstCrossing = crossings.first
        self.secondCrossing = crossings.second
    }
    
    func loadData() {
        Task {
            await fetchWeatherData()
            await fetchSunsetTime()
            calculateBestVisitTimes()
            updateCrossingWeather()
        }
    }
    
    func updateFirstCrossing(to date: Date) {
        let crossings = crossingTimeInteractor.updateFirstCrossing(to: date)
        // When the first crossing is updated, the second crossing is also updated to maintain the relative time difference
        // print("Updated First Crossing - New Date: \(crossings.first.date), Time Diff: \(crossings.first.timeDiff)")
        firstCrossing = crossings.first
        secondCrossing = crossings.second
        updateCrossingWeather()
    }
    
    func updateSecondCrossing(to date: Date) {
        secondCrossing = crossingTimeInteractor.updateSecondCrossing(to: date, relativeTo: firstCrossing)
        // When the second crossing is updated, the first crossing is also updated to maintain the relative time difference
        // print("Updated Second Crossing - New Date: \(secondCrossing.date), Time Diff: \(secondCrossing.timeDiff)")
        updateCrossingWeather()
    }
    
    func updateCrossingWeather() {
        firstCrossingWeather = getWeatherForTime(firstCrossing.date)
        secondCrossingWeather = getWeatherForTime(secondCrossing.date)
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
            
            let calendar = Calendar.current
            let now = Date()
            
            // Check if sunset has already passed for today
            if sunset < now {
                // Get tomorrow's sunset by adding 1 day
                if let tomorrowSunset = calendar.date(byAdding: .day, value: 1, to: sunset) {
                    sunsetTime = "tomorrow at \(formatter.string(from: tomorrowSunset))"
                }
            } else {
                sunsetTime = "today at \(formatter.string(from: sunset))"
            }
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
    
    func loadSavedCrossingTimes() {
        isRestoringFromBackground = true
        let (firstDiff, secondDiff) = crossingTimeInteractor.loadSavedTimeDiffs()
        let crossings = crossingTimeInteractor.calculateValidCrossingTimes(firstDiff: firstDiff, secondDiff: secondDiff)
        firstCrossing = crossings.first
        secondCrossing = crossings.second
        updateCrossingWeather()
        isRestoringFromBackground = false
    }
    
    func saveCrossingTimes() {
        let firstTimeDiff = firstCrossing.timeDiff
        let secondTimeDiff = secondCrossing.timeDiff
        crossingTimeInteractor.saveTimeDiffs(first: firstTimeDiff, second: secondTimeDiff)
    }
    
    // Get the current base date for first crossing calculations
    var firstCrossingBaseDate: Date {
        let calendar = Calendar.current
        let now = Date()
        // Round down to current minute by explicitly setting seconds to 0
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let roundedDate = calendar.date(from: components)?.addingTimeInterval(0) ?? now
        return roundedDate
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCrossingTimes()
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateCrossingTimes() {
        let now = Date()
        // Only update if first crossing is in the past
        if firstCrossing.date < now {
            let (firstDiff, secondDiff) = crossingTimeInteractor.loadSavedTimeDiffs()
            let crossings = crossingTimeInteractor.calculateValidCrossingTimes(firstDiff: firstDiff, secondDiff: secondDiff)
            firstCrossing = crossings.first
            secondCrossing = crossings.second
            updateCrossingWeather()
        }
    }
} 