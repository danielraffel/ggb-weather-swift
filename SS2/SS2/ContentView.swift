//
//  ContentView.swift
//  SS2
//
//  Created by Daniel Raffel on 1/12/25.
//

import SwiftUI
import Inject
import Charts
import Foundation

struct ContentView: View {
    @ObserveInjection var inject
    @StateObject private var presenter = WeatherPresenter(interactor: WeatherInteractor())
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Bridge Image Section
                BridgeImageView()
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                
                VStack(spacing: 16) {
                    // Sunset Info
                    if let sunset = presenter.sunsetTime {
                        Text("Next sunset at \(sunset)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 16)
                    }
                    
                    // First Crossing Card
                    CrossingCard(
                        title: "1st GGB Crossing",
                        timeDiff: $presenter.firstCrossingTimeDiff,
                        crossingTime: $presenter.firstCrossingTime,
                        weather: presenter.firstCrossingWeather,
                        onTimeChange: { presenter.updateCrossingWeather() }
                    )
                    
                    // Second Crossing Card
                    CrossingCard(
                        title: "2nd GGB Crossing",
                        timeDiff: $presenter.secondCrossingTimeDiff,
                        crossingTime: $presenter.secondCrossingTime,
                        weather: presenter.secondCrossingWeather,
                        onTimeChange: { presenter.updateCrossingWeather() }
                    )
                    
                    // Best Visit Time Section
                    BestVisitTimeView(bestTimes: presenter.bestVisitTimes)
                    
                    // Weather Chart
                    WeatherChartView(weatherData: presenter.weatherData)
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            }
        }
        .refreshable {
            await presenter.refresh()
        }
        .background(Color(.systemBackground))
        .onAppear {
            presenter.loadData()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task {
                    await presenter.refresh()
                }
            }
        }
        .enableInjection()
    }
}

// Add this custom RefreshControl view
struct RefreshControl: View {
    let coordinateSpace: CoordinateSpace
    let onRefresh: () async -> Void
    
    @State private var refresh = false
    @State private var offset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            if geo.frame(in: coordinateSpace).midY > 50 {
                Spacer()
                    .onAppear {
                        if !refresh {
                            refresh = true
                            Task {
                                await onRefresh()
                                refresh = false
                            }
                        }
                    }
            }
            
            HStack {
                Spacer()
                if refresh {
                    ProgressView()
                } else {
                    if geo.frame(in: coordinateSpace).midY > 20 {
                        Image(systemName: "arrow.down")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
            }
            .offset(y: -geo.frame(in: coordinateSpace).midY + 20)
        }
        .frame(height: 0)
    }
}

// Preview
#Preview {
    ContentView()
}
