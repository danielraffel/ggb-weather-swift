//
//  SS2App.swift
//  SS2
//
//  Created by Daniel Raffel on 1/12/25.
//

import SwiftUI
import Inject
import BackgroundTasks
import os
import WidgetKit
import WatchConnectivity

@main
struct SS2App: App {
    @ObserveInjection var inject
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "SS2App")
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .enableInjection()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, WCSessionDelegate {
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "AppDelegate")
    private let weatherInteractor: WeatherInteractorProtocol
    private let sharedDataInteractor: SharedDataInteractor
    private let appGroupIdentifier = "group.genco"
    
    override init() {
        self.weatherInteractor = WeatherInteractor()
        self.sharedDataInteractor = SharedDataInteractor()
        super.init()
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure background tasks first
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "generouscorp.ggb.backgroundRefresh", using: nil) { task in
            self.handleBackgroundTask(task as? BGAppRefreshTask)
        }
        logger.notice("📋 Registered background task: generouscorp.ggb.backgroundRefresh")
        
        let identifier = self.appGroupIdentifier
        logger.notice("📱 App launching with group: \(identifier)")
        
        // Initialize WatchConnectivity
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            logger.notice("⌚️ WCSession activated")
        }
        
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            logger.notice("📂 App group container path: \(containerURL.path)")
        } else {
            logger.error("❌ Could not access app group container: \(identifier)")
        }
        
        // Fetch data immediately and schedule refresh
        Task { [weak self] in
            guard let self = self else { return }
            self.logger.notice("🔄 Initial data fetch starting...")
            await self.refreshWeatherData()
            self.scheduleNextRefresh()
            
            // Force an immediate widget update
            WidgetCenter.shared.reloadAllTimelines()
            self.logger.notice("🔄 Requested widget timeline refresh")
        }
        
        return true
    }
    
    // WCSession delegate methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("❌ WCSession activation failed: \(error.localizedDescription)")
        } else {
            logger.notice("✅ WCSession activated: \(activationState.rawValue)")
            Task {
                do {
                    if let data = try await sharedDataInteractor.loadWeatherData() {
                        let encoder = JSONEncoder()
                        let encodedData = try encoder.encode(data)
                        session.transferUserInfo(["weatherData": encodedData])
                        logger.notice("✅ Sent initial data to watch")
                    }
                } catch {
                    logger.error("❌ Failed to send initial data: \(error)")
                }
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        logger.notice("⌚️ WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        logger.notice("⌚️ WCSession deactivated")
        // Reactivate for future use
        WCSession.default.activate()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        logger.notice("📱 Received message from watch: \(message)")
        
        if let type = message["type"] as? String {
            switch type {
            case "requestTransfer":
                Task {
                    let hasData = (try? await sharedDataInteractor.loadWeatherData()) != nil
                    replyHandler(["status": "ready", "hasData": hasData])
                    if hasData {
                        logger.notice("✅ Acknowledged transfer request with existing data")
                    } else {
                        logger.notice("⚠️ Acknowledged transfer request with no existing data")
                    }
                }
                
            case "getData":
                Task {
                    do {
                        _ = try await weatherInteractor.fetchAndCacheWeatherData()
                        if let data = try? await sharedDataInteractor.loadWeatherData() {
                            let encoder = JSONEncoder()
                            let encodedData = try encoder.encode(data)
                            
                            // Check if data is too large
                            if encodedData.count > 65536 { // WCSession message size limit
                                // Split data into chunks
                                let chunks = encodedData.chunked(into: 65000)
                                logger.notice("📦 Splitting data into \(chunks.count) chunks")
                                
                                // Send chunks sequentially
                                for (index, chunk) in chunks.enumerated() {
                                    let chunkMessage: [String: Any] = [
                                        "type": "chunk",
                                        "index": index,
                                        "total": chunks.count,
                                        "data": chunk
                                    ]
                                    session.sendMessage(chunkMessage, replyHandler: { response in
                                        self.logger.notice("✅ Chunk \(index + 1)/\(chunks.count) acknowledged: \(response)")
                                    }, errorHandler: { error in
                                        self.logger.error("❌ Failed to send chunk \(index + 1): \(error.localizedDescription)")
                                    })
                                }
                                replyHandler(["status": "chunked", "chunks": chunks.count])
                            } else {
                                replyHandler(["weatherData": encodedData])
                                logger.notice("✅ Sent weather data to watch")
                            }
                        } else {
                            replyHandler(["error": "No data available"])
                            logger.error("❌ No weather data available")
                        }
                    } catch {
                        replyHandler(["error": error.localizedDescription])
                        logger.error("❌ Failed to fetch weather data: \(error)")
                    }
                }
                
            default:
                replyHandler(["status": "unknown"])
                logger.error("❌ Unknown request type")
            }
        } else {
            replyHandler(["status": "error", "message": "missing type"])
            logger.error("❌ Message missing type field")
        }
    }
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask?) {
        guard let refreshTask = task else { return }
        
        // Set up expiration handler first
        refreshTask.expirationHandler = {
            refreshTask.setTaskCompleted(success: false)
            self.logger.error("❌ Background task expired")
        }
        
        // Perform refresh
        Task {
            do {
                _ = try await self.weatherInteractor.fetchAndCacheWeatherData()
                self.scheduleNextRefresh()
                refreshTask.setTaskCompleted(success: true)
                self.logger.notice("✅ Background refresh completed successfully")
            } catch {
                self.logger.error("❌ Background refresh failed: \(error.localizedDescription)")
                refreshTask.setTaskCompleted(success: false)
            }
        }
    }
    
    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "generouscorp.ggb.backgroundRefresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        if UIApplication.shared.applicationState == .background {
            do {
                try BGTaskScheduler.shared.submit(request)
                logger.notice("⏱️ Scheduled next background refresh")
            } catch {
                logger.error("❌ Could not schedule refresh: \(error.localizedDescription)")
            }
        } else {
            logger.notice("⏱️ Skipping background refresh schedule while app is active")
        }
    }
    
    private func refreshWeatherData() async {
        logger.notice("🌤️ Starting weather data refresh...")
        do {
            _ = try await weatherInteractor.fetchAndCacheWeatherData()
            logger.notice("✅ Successfully refreshed and cached weather data")
            WidgetCenter.shared.reloadAllTimelines()
            logger.notice("🔄 Requested widget timeline refresh")
        } catch {
            logger.error("❌ Failed to refresh weather data: \(error.localizedDescription)")
        }
    }
    
    // Handle app state changes
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.notice("📱 App entered background")
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
            self.scheduleNextRefresh()
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.notice("📱 App will enter foreground")
        Task {
            await refreshWeatherData()
        }
    }
}

extension Data {
    func chunked(into size: Int) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        
        while offset < count {
            let chunkSize = Swift.min(size, count - offset)
            let chunk = self[offset..<(offset + chunkSize)]
            chunks.append(Data(chunk))
            offset += chunkSize
        }
        
        return chunks
    }
}
