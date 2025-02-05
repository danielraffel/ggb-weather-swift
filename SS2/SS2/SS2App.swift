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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .enableInjection()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, WCSessionDelegate {
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "AppDelegate")
    private let interactor = WeatherInteractor()
    private let appGroupIdentifier = "group.genco"
    private let sharedDataInteractor = SharedDataInteractor()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
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
        
        // Configure background tasks
        configureBackgroundTasks()
        
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
        
        if let request = message["request"] as? String {
            switch request {
            case "weatherData":
                Task {
                    do {
                        if let data = try await sharedDataInteractor.loadWeatherData() {
                            let encoder = JSONEncoder()
                            let encodedData = try encoder.encode(data)
                            let chunks = encodedData.chunked(into: 16384)
                            replyHandler(["status": "ready", "chunks": chunks.count])
                            logger.notice("✅ Ready to send \(chunks.count) chunks")
                        } else {
                            replyHandler(["status": "nodata"])
                            logger.error("❌ No weather data available")
                        }
                    } catch {
                        replyHandler(["status": "error", "message": error.localizedDescription])
                        logger.error("❌ Failed to prepare data: \(error.localizedDescription)")
                    }
                }
                
            case "chunk":
                if let index = message["index"] as? Int {
                    Task {
                        do {
                            if let data = try await sharedDataInteractor.loadWeatherData() {
                                let encoder = JSONEncoder()
                                let encodedData = try encoder.encode(data)
                                let chunks = encodedData.chunked(into: 16384)
                                
                                if index < chunks.count {
                                    replyHandler(["type": "chunk", "data": chunks[index], "index": index])
                                    logger.notice("✅ Sent chunk \(index + 1)/\(chunks.count)")
                                } else {
                                    replyHandler(["status": "error", "message": "Invalid chunk index"])
                                    logger.error("❌ Invalid chunk index requested: \(index)")
                                }
                            } else {
                                replyHandler(["status": "nodata"])
                                logger.error("❌ No weather data available for chunk request")
                            }
                        } catch {
                            replyHandler(["status": "error", "message": error.localizedDescription])
                            logger.error("❌ Failed to send chunk: \(error.localizedDescription)")
                        }
                    }
                } else {
                    replyHandler(["status": "error", "message": "Invalid chunk request"])
                    logger.error("❌ Invalid chunk request received")
                }
                
            default:
                replyHandler(["status": "unknown"])
                logger.error("❌ Unknown request type: \(request)")
            }
        } else {
            replyHandler(["status": "invalid"])
            logger.error("❌ Invalid message format received")
        }
    }
    
    private func configureBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "generouscorp.ggb.backgroundRefresh", using: .main) { [weak self] task in
            guard let self = self,
                  let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleWeatherRefresh(task: refreshTask)
        }
        logger.notice("📋 Registered background task: generouscorp.ggb.backgroundRefresh")
        
        // Enable background fetch
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.set(true, forKey: "\(bundleIdentifier).BackgroundRefreshEnabled")
            logger.notice("✅ Enabled background refresh for \(bundleIdentifier)")
        }
    }
    
    private func handleWeatherRefresh(task: BGAppRefreshTask) {
        logger.notice("⏰ Background refresh task started")
        
        // Set up task expiration
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
            self.logger.error("❌ Background task expired")
        }
        
        // Perform refresh
        Task {
            await refreshWeatherData()
            scheduleNextRefresh()
            task.setTaskCompleted(success: true)
            logger.notice("✅ Background task completed")
        }
    }
    
    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "generouscorp.ggb.backgroundRefresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            // Cancel any existing requests first
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "generouscorp.ggb.backgroundRefresh")
            
            // Submit new request
            try BGTaskScheduler.shared.submit(request)
            logger.notice("⏱️ Scheduled next background refresh for \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            logger.error("❌ Could not schedule weather refresh: \(error.localizedDescription), code: \((error as NSError).code)")
        }
    }
    
    private func refreshWeatherData() async {
        logger.notice("🌤️ Starting weather data refresh...")
        do {
            let data = try await interactor.fetchAndCacheWeatherData()
            logger.notice("✅ Successfully refreshed and cached weather data. Items: \(data.count)")
            
            // Force widget timeline refresh
            WidgetCenter.shared.reloadAllTimelines()
            logger.notice("🔄 Requested widget timeline refresh")
        } catch {
            logger.error("❌ Failed to refresh weather data: \(error.localizedDescription)")
        }
    }
    
    // Handle app state changes
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.notice("📱 App entered background")
        scheduleNextRefresh()
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
