import Foundation

// Re-export all public types
@_exported import struct Foundation.Date
@_exported import struct Foundation.Data
@_exported import struct Foundation.URL
@_exported import class Foundation.URLSession
@_exported import class Foundation.JSONEncoder
@_exported import class Foundation.JSONDecoder
@_exported import class Foundation.UserDefaults

// Public types from WeatherModels
public typealias WeatherData = SharedWeatherData
public typealias CrossingWeather = SharedCrossingWeather
public typealias BestVisitTime = SharedBestVisitTime

// Public types from SharedCacheModels
public typealias CachedWeatherData = SharedCachedWeatherData

// Public protocols and implementations
public typealias SharedDataInteractorProtocol = SharedDataInteracting
public typealias WeatherInteractorProtocol = WeatherInteracting 