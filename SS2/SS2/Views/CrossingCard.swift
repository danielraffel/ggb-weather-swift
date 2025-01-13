import SwiftUI
import Inject
import Combine

struct CrossingCard: View {
    @ObserveInjection var inject
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
        
        _selectedHours = State(initialValue: timeDiff.wrappedValue.hours)
        _selectedMinutes = State(initialValue: timeDiff.wrappedValue.minutesPart)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            HStack(spacing: 0) {  // Main spacing between all elements - adjust this for overall gaps
                Text("in")
                    .foregroundColor(.secondary)
                    .padding(.trailing, -15)  // Space between "in" and hours - adjust this number
                
                Picker("Hours", selection: $selectedHours) {
                    ForEach(0..<24) { hour in
                        Text("\(hour)h")
                            .fixedSize()  // Prevents "h" from wrapping
                            .frame(width: 45, alignment: .leading)  // Width of hours text - adjust this
                            .tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)  // Overall hours picker width - adjust this
                .padding(.trailing, -32) // Add negative padding to reduce space between h and m
                
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(0..<60) { minute in
                        Text("\(minute)m")
                            .monospacedDigit()
                            .fixedSize()  // Prevents "m" from wrapping
                            .frame(width: 60, alignment: .leading)  // Width of minutes text - adjust this
                            .tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)  // Overall minutes picker width - adjust this
                .padding(.trailing, -18) // Add negative padding to reduce space between m and "at"
                
                Text("at")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)  // Space around "at" - adjust this
                    .padding(.trailing, -2) // Add negative padding to reduce space between "at" and the date picker
                
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
        .onChange(of: timeDiff) { newValue in
            selectedHours = newValue.hours
            selectedMinutes = newValue.minutesPart
        }
        .enableInjection()
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