//
//  GGB_Watch_AppApp.swift
//  GGB Watch App Watch App
//
//  Created by Daniel Raffel on 2/1/25.
//

import SwiftUI
import WidgetKit
import WatchKit
import os
import WatchConnectivity

@main
struct GGB_Watch_AppApp: App {
    @StateObject private var sessionDelegate = WatchSessionDelegate()
    private let dataInteractor = SharedDataInteractor()
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "WatchApp")
    
    var body: some Scene {
        WindowGroup {
            GGBWatchAppView()
                .task {
                    await loadInitialData()
                }
        }
    }
    
    private func loadInitialData() async {
        logger.notice("⌚️ Loading initial data...")
        
        // Wait for WCSession to be activated and reachable
        while !WCSession.default.isReachable {
            logger.notice("⏳ Waiting for WCSession to become reachable...")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
            
            // Check if we have cached data while waiting
            if let cachedData = try? await dataInteractor.loadWeatherData() {
                logger.notice("✅ Found cached data while waiting for WCSession: \(cachedData.weatherData.count) items")
                WidgetCenter.shared.reloadAllTimelines()
                return
            }
        }
        
        logger.notice("📱 WCSession is reachable, requesting data...")
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // First, request data transfer start
                WCSession.default.sendMessage(["type": "requestTransfer"]) { reply in
                    if let status = reply["status"] as? String, status == "ready" {
                        Task {
                            do {
                                // Now request the actual data
                                try await self.requestDataInChunks()
                                continuation.resume()
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        continuation.resume(throwing: WatchConnectionError.connectionLost)
                    }
                } errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            logger.error("❌ Failed to get data: \(error.localizedDescription)")
            // Try to load cached data as fallback
            if let cachedData = try? await dataInteractor.loadWeatherData() {
                logger.notice("✅ Using cached data after WCSession error: \(cachedData.weatherData.count) items")
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
    
    private func requestDataInChunks() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WCSession.default.sendMessage(["type": "getData"]) { reply in
                if let encodedData = reply["weatherData"] as? Data {
                    Task {
                        do {
                            let decodedData = try JSONDecoder().decode(CachedWeatherData.self, from: encodedData)
                            try await self.dataInteractor.saveWeatherData(decodedData)
                            logger.notice("✅ Received and saved data from iOS app: \(decodedData.weatherData.count) items")
                            WidgetCenter.shared.reloadAllTimelines()
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    continuation.resume(throwing: WatchConnectionError.connectionLost)
                }
            } errorHandler: { error in
                continuation.resume(throwing: error)
            }
        }
    }

    private enum WatchConnectionError: Error {
        case connectionLost
    }

    // Helper function for timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self, body: { group in
            group.addTask(priority: .userInitiated) {
                try await operation()
            }
            
            group.addTask(priority: .userInitiated) {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        })
    }

    private struct TimeoutError: Error {}
}

class WatchSessionDelegate: NSObject, ObservableObject, WCSessionDelegate {
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "WatchApp")
    private let sharedDataInteractor = SharedDataInteractor()
    private var dataBuffer = Data()
    private var receivedChunks = 0
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("❌ WCSession activation failed: \(error.localizedDescription)")
            return
        }
        logger.notice("✅ WCSession activated with state: \(activationState.rawValue)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        logger.notice("📥 Received message: \(message.keys)")
        if let type = message["type"] as? String {
            switch type {
            case "chunk":
                if let chunkData = message["data"] as? Data,
                   let index = message["index"] as? Int,
                   let total = message["total"] as? Int {
                    dataBuffer.append(chunkData)
                    receivedChunks += 1
                    logger.notice("✅ Received chunk \(index + 1)/\(total) (size: \(chunkData.count) bytes)")
                    
                    if receivedChunks == total {
                        logger.notice("🎯 All chunks received, processing data...")
                        processCompleteData()
                    }
                    replyHandler(["status": "received", "chunk": index])
                } else {
                    logger.error("❌ Received malformed chunk data")
                    replyHandler(["status": "error", "message": "malformed chunk"])
                }
                
            default:
                logger.error("❌ Unknown message type: \(type)")
                replyHandler(["status": "unknown"])
            }
        } else if let weatherData = message["weatherData"] as? Data {
            Task {
                do {
                    let decodedData = try JSONDecoder().decode(CachedWeatherData.self, from: weatherData)
                    try await sharedDataInteractor.saveWeatherData(decodedData)
                    logger.notice("✅ Saved received weather data with \(decodedData.weatherData.count) items")
                    WidgetCenter.shared.reloadAllTimelines()
                    replyHandler(["status": "success"])
                } catch {
                    logger.error("❌ Failed to process received weather data: \(error)")
                    replyHandler(["status": "error", "message": error.localizedDescription])
                }
            }
        } else {
            logger.error("❌ Message missing type field")
            replyHandler(["status": "error", "message": "missing type"])
        }
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        logger.notice("📦 Received user info transfer")
        if let weatherData = userInfo["weatherData"] as? Data {
            Task {
                do {
                    let decodedData = try JSONDecoder().decode(CachedWeatherData.self, from: weatherData)
                    try await sharedDataInteractor.saveWeatherData(decodedData)
                    logger.notice("✅ Saved received weather data")
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    logger.error("❌ Failed to process received weather data: \(error)")
                }
            }
        }
    }
    
    private func processCompleteData() {
        Task {
            do {
                logger.notice("🔄 Processing complete data (size: \(self.dataBuffer.count) bytes)")
                let decodedData = try JSONDecoder().decode(CachedWeatherData.self, from: self.dataBuffer)
                logger.notice("📊 Decoded weather data contains \(decodedData.weatherData.count) items")
                
                let existingData = try? await sharedDataInteractor.loadWeatherData()
                logger.notice("🖼️ Bridge image status: \(existingData?.bridgeImage != nil ? "Present" : "Missing")")
                
                let newData = CachedWeatherData(
                    weatherData: decodedData.weatherData,
                    bridgeImage: existingData?.bridgeImage
                )
                try await sharedDataInteractor.saveWeatherData(newData)
                logger.notice("✅ Saved complete weather data with \(decodedData.weatherData.count) items")
                logger.notice("  • Bridge image preserved: \(existingData?.bridgeImage != nil)")
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                logger.error("❌ Failed to process complete data: \(error)")
                logger.error("  • Error details: \(String(describing: error))")
            }
            
            // Clear the buffer
            dataBuffer = Data()
            receivedChunks = 0
        }
    }
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        logger.notice("📥 Received file")
        if file.metadata?["type"] as? String == "bridgeImage" {
            Task {
                do {
                    let imageData = try Data(contentsOf: file.fileURL)
                    logger.notice("🖼️ Received bridge image (size: \(imageData.count) bytes)")
                    
                    if let existingData = try? await sharedDataInteractor.loadWeatherData() {
                        let newData = CachedWeatherData(
                            weatherData: existingData.weatherData,
                            bridgeImage: imageData
                        )
                        try? await sharedDataInteractor.saveWeatherData(newData)
                        logger.notice("✅ Saved received bridge image")
                        WidgetCenter.shared.reloadAllTimelines()
                    } else {
                        logger.error("❌ No existing weather data to attach bridge image to")
                    }
                } catch {
                    logger.error("❌ Failed to process bridge image: \(error)")
                }
            }
        }
    }
}