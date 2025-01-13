//
//  SS2App.swift
//  SS2
//
//  Created by Daniel Raffel on 1/12/25.
//

import SwiftUI
import Inject

@main
struct SS2App: App {
    @ObserveInjection var inject
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .enableInjection()
        }
    }
}
