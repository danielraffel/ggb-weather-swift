//
//  ContentView.swift
//  GGB Watch App Watch App
//
//  Created by Daniel Raffel on 2/1/25.
//

import SwiftUI
import WidgetKit

struct GGBWatchAppView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("GGB Weather")
                .font(.title3)
                .bold()
            
            Image(systemName: "bridge.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            
            Text("Check the widget for current weather conditions")
                .multilineTextAlignment(.center)
                .font(.caption)
                .padding(.horizontal)
        }
    }
}

#Preview {
    GGBWatchAppView()
}
