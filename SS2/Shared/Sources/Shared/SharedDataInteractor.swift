import Foundation
import os
import WidgetKit

public protocol SharedDataInteracting {
    func loadWeatherData(maxRetries: Int, retryDelay: TimeInterval) async throws -> SharedCachedWeatherData?
    func saveWeatherData(_ data: SharedCachedWeatherData) async throws
}

public final class SharedDataInteractor: SharedDataInteracting {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "SharedDataInteractor")
    private let maxCacheAge: TimeInterval = 15 * 60 // 15 minutes
    private let appGroupIdentifier = "group.genco"
    private let defaults: UserDefaults
    private let weatherDataKey = "cachedWeatherData"
    private let queue = DispatchQueue(label: "com.danielraffel.ggbweather.shareddata")
    
    public init(defaults: UserDefaults? = nil) {
        logger.notice("🔧 Initializing SharedDataInteractor...")
        
        // Use provided defaults, or try to get shared defaults, or fall back to standard
        if let defaults = defaults {
            self.defaults = defaults
        } else if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            self.defaults = sharedDefaults
        } else {
            self.defaults = .standard
            logger.error("❌ Failed to access shared defaults, falling back to standard")
        }
        
        // Debug app group access
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            logger.notice("📂 App group container path: \(containerURL.path)")
            
            // Create Preferences directory if it doesn't exist
            let prefsURL = containerURL.appendingPathComponent("Library/Preferences")
            do {
                try fileManager.createDirectory(at: prefsURL, withIntermediateDirectories: true)
                logger.notice("✅ Preferences directory ensured at: \(prefsURL.path)")
            } catch {
                logger.error("❌ Failed to create preferences directory: \(error.localizedDescription)")
            }
        }
        
        logger.notice("✅ SharedDataInteractor initialized successfully")
    }
    
    @SharedDataActor
    public func saveWeatherData(_ data: SharedCachedWeatherData) async throws {
        logger.notice("💾 Attempting to save weather data...")
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let encodedData = try JSONEncoder().encode(data)
                    self.defaults.set(encodedData, forKey: self.weatherDataKey)
                    self.defaults.synchronize() // Ensure data is written immediately
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    @SharedDataActor
    public func loadWeatherData(maxRetries: Int = 3, retryDelay: TimeInterval = 1.0) async throws -> SharedCachedWeatherData? {
        var retryCount = 0
        var lastError: Error?
        
        while retryCount < maxRetries {
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    queue.async {
                        guard let data = self.defaults.data(forKey: self.weatherDataKey) else {
                            continuation.resume(returning: nil)
                            return
                        }
                        
                        do {
                            let decoder = JSONDecoder()
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                            formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
                            formatter.locale = Locale(identifier: "en_US_POSIX")
                            decoder.dateDecodingStrategy = .formatted(formatter)
                            
                            let cachedData = try decoder.decode(SharedCachedWeatherData.self, from: data)
                            continuation.resume(returning: cachedData)
                        } catch {
                            self.logger.error("❌ Failed to decode cached data: \(error)")
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } catch {
                lastError = error
                retryCount += 1
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NSError(domain: "com.danielraffel.ggbweather", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load weather data after \(maxRetries) attempts"])
    }
    
    private func refreshWeatherData() async {
        logger.notice("🌤️ Starting weather data refresh...")
        do {
            if try await loadWeatherData() != nil {
                WidgetCenter.shared.reloadAllTimelines()
                logger.notice("✅ Refreshed data")
            }
        } catch {
            logger.error("❌ Failed to refresh weather data: \(error.localizedDescription)")
        }
    }
}