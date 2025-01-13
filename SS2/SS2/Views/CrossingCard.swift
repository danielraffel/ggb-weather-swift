import SwiftUI
import Combine

struct CrossingCard: View {
    let title: String
    @Binding var timeDiff: TimeDiff
    @Binding var crossingTime: Date
    let weather: CrossingWeather?
    let onTimeChange: () -> Void
    
    @State private var debounceTimer: Timer?
    @State private var selectedHours: Int
    @State private var selectedMinutes: Int
    
    init(title: String, timeDiff: Binding<TimeDiff>, crossingTime: Binding<Date>, weather: CrossingWeather?, onTimeChange: @escaping () -> Void) {
        self.title = title
        self._timeDiff = timeDiff
        self._crossingTime = crossingTime
        self.weather = weather
        self.onTimeChange = onTimeChange
        
        // Initialize the hours and minutes from timeDiff
        let hours = timeDiff.wrappedValue.hours
        let minutes = timeDiff.wrappedValue.minutesPart
        _selectedHours = State(initialValue: hours)
        _selectedMinutes = State(initialValue: minutes)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            HStack {
                Text("in")
                    .foregroundColor(.secondary)
                
                Picker("Hours", selection: $selectedHours) {
                    ForEach(0..<24) { hour in
                        Text("\(hour)h").tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 70)
                
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(0..<60) { minute in
                        Text("\(minute)m")
                            .monospacedDigit()
                            .tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                
                Text("at")
                    .foregroundColor(.secondary)
                
                DatePicker("", selection: $crossingTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
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
        .onChange(of: selectedHours) { _ in
            updateTimeDiff()
        }
        .onChange(of: selectedMinutes) { _ in
            updateTimeDiff()
        }
    }
    
    private func updateTimeDiff() {
        timeDiff = .combined(hours: selectedHours, minutes: selectedMinutes)
        debounceTimeChange()
    }
    
    private func debounceTimeChange() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            onTimeChange()
        }
    }
} 