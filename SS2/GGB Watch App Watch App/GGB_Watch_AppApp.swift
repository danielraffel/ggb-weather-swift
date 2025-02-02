//
//  GGB_Watch_AppApp.swift
//  GGB Watch App Watch App
//
//  Created by Daniel Raffel on 2/1/25.
//

import SwiftUI
import WidgetKit

@main
struct GGB_Watch_AppApp: App {
    init() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    var body: some Scene {
        WindowGroup {
            GGBWatchAppView()
        }
    }
}