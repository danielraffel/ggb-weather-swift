import SwiftUI
import Inject
import Combine

struct CrossingCard: View {
    @ObserveInjection var inject
    let title: String
    @Binding var crossingTime: CrossingTime
    let weather: CrossingWeather?
    let onTimeChange: (Date) -> Void
    let baseDate: Date  // Base date for calculating time diff
    
    @State private var selectedHours: Int
    @State private var selectedMinutes: Int
    @State private var selectedTime: Date
    @State private var debounceTimer: Timer?
    
    init(title: String, crossingTime: Binding<CrossingTime>, weather: CrossingWeather?, baseDate: Date, onTimeChange: @escaping (Date) -> Void) {
        self.title = title
        self._crossingTime = crossingTime
        self.weather = weather
        self.baseDate = baseDate
        self.onTimeChange = onTimeChange
        
        // Initialize state with current crossing time values
        let timeDiff = crossingTime.wrappedValue.timeDiff
        switch timeDiff {
        case .combined(let h, let m):
            _selectedHours = State(initialValue: h)
            _selectedMinutes = State(initialValue: m)
        }
        _selectedTime = State(initialValue: crossingTime.wrappedValue.date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            HStack(spacing: 0) {
                Text("in")
                    .foregroundColor(.secondary)
                    .padding(.trailing, -15)
                
                Picker("Hours", selection: $selectedHours) {
                    ForEach(0..<24) { hour in
                        Text("\(hour)h")
                            .fixedSize()
                            .frame(width: 45, alignment: .leading)
                            .tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .padding(.trailing, -32)
                
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(0..<60) { minute in
                        Text("\(minute)m")
                            .monospacedDigit()
                            .fixedSize()
                            .frame(width: 60, alignment: .leading)
                            .tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .padding(.trailing, -18)
                
                Text("at")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.trailing, -2)
                
                DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
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
            updateFromDropdowns()
        }
        .onChange(of: selectedMinutes) { _ in
            updateFromDropdowns()
        }
        .onChange(of: selectedTime) { newTime in
            updateFromTimePicker(newTime)
        }
        .onChange(of: crossingTime) { newValue in
            // Only update UI if the values actually changed
            if abs(newValue.date.timeIntervalSince(selectedTime)) > 1 {
                selectedTime = newValue.date
                switch newValue.timeDiff {
                case .combined(let h, let m):
                    selectedHours = h
                    selectedMinutes = m
                }
            }
        }
        .enableInjection()
    }
    
    private func updateFromDropdowns() {
        // When dropdowns change, calculate new date based on time diff from base date
        let timeDiff = TimeDiff.combined(hours: selectedHours, minutes: selectedMinutes)
        let newDate = timeDiff.applying(to: baseDate)
        
        // Only update if the date would actually change
        if abs(newDate.timeIntervalSince(selectedTime)) > 1 {
            selectedTime = newDate
            debounceTimeChange(newDate)
        }
    }
    
    private func updateFromTimePicker(_ newTime: Date) {
        // When time picker changes, calculate time diff from base date
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: baseDate, to: newTime)
        
        // Update dropdowns to reflect new time diff
        selectedHours = components.hour ?? 0
        selectedMinutes = components.minute ?? 0
        
        debounceTimeChange(newTime)
    }
    
    private func debounceTimeChange(_ newTime: Date) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            onTimeChange(newTime)
        }
    }
} 