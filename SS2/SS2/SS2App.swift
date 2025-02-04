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

class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "generouscorp.SS2.ggbweather", category: "AppDelegate")
    private let interactor = WeatherInteractor()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        logger.notice("📱 App launching...")
        
        // Configure background tasks
        configureBackgroundTasks()
        
        // Fetch data immediately and schedule refresh
        Task {
            logger.notice("🔄 Initial data fetch starting...")
            await refreshWeatherData()
            scheduleNextRefresh()
            
            // Force an immediate widget update
            WidgetCenter.shared.reloadAllTimelines()
            logger.notice("🔄 Requested widget timeline refresh")
        }
        
        return true
    }
    
    private func configureBackgroundTasks() {
        // Register background fetch task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "generouscorp.SS2.weatherRefresh", using: nil) { task in
            self.handleWeatherRefresh(task: task as! BGAppRefreshTask)
        }
        logger.notice("📋 Registered background task: generouscorp.SS2.weatherRefresh")
        
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
        let request = BGAppRefreshTaskRequest(identifier: "generouscorp.SS2.weatherRefresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.notice("⏱️ Scheduled next background refresh for \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            logger.error("❌ Could not schedule weather refresh: \(error.localizedDescription)")
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
