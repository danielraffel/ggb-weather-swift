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
        .background(Color(.systemBackground))
        .onAppear {
            presenter.loadData()
        }
        .enableInjection()
    }
}

// Preview
#Preview {
    ContentView()
}
