import Foundation
import SwiftUI

@MainActor
public final class WatchDataPresenter: ObservableObject {
    @Published public private(set) var weatherData: [WeatherData] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isLoading = false
    
    private let interactor: WatchDataInteractorProtocol
    
    private init(interactor: WatchDataInteractorProtocol) {
        self.interactor = interactor
    }
    
    public static func create() -> WatchDataPresenter {
        let interactor = WatchDataInteractor()
        return WatchDataPresenter(interactor: interactor)
    }
    
    public func loadWeatherData() {
        Task {
            self.isLoading = true
            self.errorMessage = nil
            
            do {
                self.weatherData = try await self.interactor.loadWeatherData()
            } catch SharedDataError.cacheEmpty {
                self.errorMessage = "No weather data available"
            } catch SharedDataError.cacheStale {
                self.errorMessage = "Weather data is outdated"
            } catch {
                self.errorMessage = "Failed to load weather data"
            }
            
            self.isLoading = false
        }
    }
    
    public var currentWeather: WeatherData? {
        let now = Date()
        return weatherData.first { weatherData in
            weatherData.time > now
        }
    }
} 