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
        VStack(alignment: .leading, spacing: 12) { // spacing between the card and the text
            Text(title)
                .font(.headline)
            
            HStack(spacing: 0) {  // Main spacing between all elements - adjust this for overall gaps
                Text("in")
                    .foregroundColor(.secondary)
                    .padding(.trailing, -20)  // Space between "in" and hours - adjust this number
                
                Picker("Hours", selection: $selectedHours) {
                    ForEach(0..<24) { hour in
                        Text("\(hour)h")
                            .fixedSize()  // Prevents "h" from wrapping
                            .frame(width: 45, alignment: .leading)  // Width of hour picker
                            .tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)  // Width of hour picker
                .padding(.trailing, -35)  // Space between hour picker and minutes in this case negative
                
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(0..<60) { minute in
                        Text("\(minute)m")
                            .monospacedDigit()
                            .fixedSize()  // Prevents "m" from wrapping
                            .frame(width: 60, alignment: .leading)  // Width of minute picker
                            .tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 85)  // Width of minute picker
                .padding(.trailing, -10)  // Space between minute picker and "at"
                
                Text("at")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)  // Space between "at" and date picker
                    .padding(.trailing, -0)  // Space between "at" and date picker
                
                DatePicker("", 
                    selection: $selectedTime,
                    in: baseDate...Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: baseDate)!,
                    displayedComponents: .hourAndMinute
                )
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
        .onChange(of: selectedHours) { oldValue, newValue in
            updateFromDropdowns()
        }
        .onChange(of: selectedMinutes) { oldValue, newValue in
            updateFromDropdowns()
        }
        .onChange(of: selectedTime) { oldValue, newValue in
            updateFromTimePicker(newValue)
        }
        .onChange(of: crossingTime) { oldValue, newValue in
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
        
        // Only update if the date would actually change significantly
        if abs(newDate.timeIntervalSince(selectedTime)) > 1 {
            // Prevent feedback loop by checking if new time would be valid
            if newDate >= baseDate {
                selectedTime = newDate
                debounceTimeChange(newDate)
            } else {
                // Reset to current values if invalid
                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute], from: baseDate, to: selectedTime)
                selectedHours = components.hour ?? 0
                selectedMinutes = components.minute ?? 0
            }
        }
    }
    
    private func updateFromTimePicker(_ newTime: Date) {
        // When time picker changes, calculate time diff from base date
        let calendar = Calendar.current
        
        // Only update if the time would be valid
        if newTime >= baseDate {
            let components = calendar.dateComponents([.hour, .minute], from: baseDate, to: newTime)
            
            // Only update dropdowns if values would actually change
            let newHours = components.hour ?? 0
            let newMinutes = components.minute ?? 0
            if newHours != selectedHours || newMinutes != selectedMinutes {
                selectedHours = newHours
                selectedMinutes = newMinutes
            }
            
            debounceTimeChange(newTime)
        } else {
            // Reset time picker to previous valid time
            selectedTime = max(baseDate, selectedTime)
        }
    }
    
    private func debounceTimeChange(_ newTime: Date) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            onTimeChange(newTime)
        }
    }
} 