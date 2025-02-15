import Foundation

public protocol WatchDataInteractorProtocol {
    func loadWeatherData() async throws -> [WeatherData]
}

@MainActor
public final class WatchDataInteractor: WatchDataInteractorProtocol {
    private let sharedDataInteractor: SharedDataInteractorProtocol
    
    public init(sharedDataInteractor: SharedDataInteractorProtocol = SharedDataInteractor()) {
        self.sharedDataInteractor = sharedDataInteractor
    }
    
    public func loadWeatherData() async throws -> [WeatherData] {
        guard let cachedData = try await sharedDataInteractor.loadWeatherData(maxRetries: 3, retryDelay: 2.0) else {
            throw SharedDataError.cacheEmpty
        }
        return cachedData.weatherData
    }
} 