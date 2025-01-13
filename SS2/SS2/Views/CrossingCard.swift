import SwiftUI
import Combine

struct CrossingCard: View {
    let title: String
    @Binding var timeDiff: TimeDiff
    @Binding var crossingTime: Date
    let weather: CrossingWeather?
    let onTimeChange: () -> Void
    
    @State private var debounceTimer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            HStack {
                Text("in")
                    .foregroundColor(.secondary)
                
                Picker("Time Difference", selection: $timeDiff) {
                    ForEach(0..<24) { hour in
                        Text("\(hour)h").tag(TimeDiff.hours(hour))
                    }
                    ForEach(0..<60) { minute in
                        Text("\(minute)m").tag(TimeDiff.minutes(minute))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: timeDiff) { newValue in
                    debounceTimeChange()
                }
                
                Text("at")
                    .foregroundColor(.secondary)
                
                DatePicker("", selection: $crossingTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: crossingTime) { newValue in
                        debounceTimeChange()
                    }
            }
            
            if let weather = weather {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature: \(weather.temperature, specifier: "%.1f")°F")
                    Text("Wind Speed: \(weather.windSpeed, specifier: "%.1f") mph")
                    Text("Precipitation: \(weather.precipitationProbability, specifier: "%.0f")%")
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func debounceTimeChange() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            onTimeChange()
        }
    }
} 