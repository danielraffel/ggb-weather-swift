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
        
        while true {
            if let data = try? await dataInteractor.loadWeatherData() {
                logger.notice("✅ Loaded data with \(data.weatherData.count) items")
                WidgetCenter.shared.reloadAllTimelines()
                return
            }
            
            logger.notice("📱 Requesting data from iOS app...")
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    WCSession.default.sendMessage(["request": "weatherData"]) { reply in
                        if let encodedData = reply["weatherData"] as? Data {
                            Task {
                                do {
                                    let decodedData = try JSONDecoder().decode(CachedWeatherData.self, from: encodedData)
                                    try await self.dataInteractor.saveWeatherData(decodedData)
                                    logger.notice("✅ Received and saved data from iOS app")
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
                return
            } catch {
                logger.error("❌ Failed to get data: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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
    private var expectedChunks = 0
    private var receivedChunks = 0
    
    // Add public accessor for receivedChunks
    var currentReceivedChunks: Int {
        receivedChunks
    }
    
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
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        logger.notice("�� Received user info transfer")
        if let weatherData = userInfo["weatherData"] as? Data {
            Task {
                do {
                    let decodedData = try JSONDecoder().decode(CachedWeatherData.self, from: weatherData)
                    let existingData = try? await sharedDataInteractor.loadWeatherData()
                    let newData = CachedWeatherData(
                        weatherData: decodedData.weatherData,
                        bridgeImage: existingData?.bridgeImage
                    )
                    try await sharedDataInteractor.saveWeatherData(newData)
                    logger.notice("✅ Saved received weather data")
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    logger.error("❌ Failed to process received weather data: \(error)")
                }
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        logger.notice("📥 Received message: \(message.keys)")
        if let type = message["type"] as? String {
            switch type {
            case "startTransfer":
                self.expectedChunks = message["chunks"] as? Int ?? 0
                logger.notice("🔄 Starting transfer with \(self.expectedChunks) expected chunks")
                self.dataBuffer = Data()
                self.receivedChunks = 0
                replyHandler(["status": "ready"])
                
            case "chunk":
                if let chunkData = message["data"] as? Data,
                   let index = message["index"] as? Int {
                    self.dataBuffer.append(chunkData)
                    self.receivedChunks += 1
                    logger.notice("✅ Received chunk \(index + 1)/\(self.expectedChunks) (size: \(chunkData.count) bytes)")
                    
                    if self.receivedChunks == self.expectedChunks {
                        logger.notice("🎯 All chunks received, processing data...")
                        self.processCompleteData()
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
        } else {
            logger.error("❌ Message missing type field")
            replyHandler(["status": "error", "message": "missing type"])
        }
    }

    // Remove the duplicate session(_:didReceive:) method at line 187
    // Keep only the one with file: WCSessionFile parameter
    
    private func processCompleteData() {
        Task {
            do {
                logger.notice("🔄 Processing complete data (size: \(self.dataBuffer.count) bytes)")
                let decodedData = try JSONDecoder().decode(CachedWeatherData.self, from: self.dataBuffer)
                logger.notice("📊 Decoded weather data contains:")
                logger.notice("  • Number of weather entries: \(decodedData.weatherData.count)")
                // Remove timestamp check since it's not available
                
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

    // This is the only implementation we should keep for handling files
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