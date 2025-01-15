import SwiftUI
import Charts
import Inject

struct WeatherChartView: View {
    @ObserveInjection var inject
    let weatherData: [WeatherData]
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter
    }()
    
    var filteredData: [WeatherData] {
        weatherData.filter { data in
            let hour = Calendar.current.component(.hour, from: data.time)
            return hour >= 5 && hour <= 21
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Weather Forecast")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            
            if #available(iOS 16.0, *) {
                chartView
                    .padding(.bottom, 16)
            } else {
                Text("Charts require iOS 16.0 or later")
                    .foregroundColor(.secondary)
                    .padding(16)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .enableInjection()
    }
    
    @available(iOS 16.0, *)
    private var chartView: some View {
        Chart {
            ForEach(filteredData) { data in
                LineMark(
                    x: .value("Time", data.time),
                    y: .value("Temperature (°F)", data.temperature)
                )
                .foregroundStyle(by: .value("Metric", "Temperature (°F)"))
            }
            
            ForEach(filteredData) { data in
                LineMark(
                    x: .value("Time", data.time),
                    y: .value("Cloud Cover (%)", data.cloudCover)
                )
                .foregroundStyle(by: .value("Metric", "Cloud Cover (%)"))
            }
            
            ForEach(filteredData) { data in
                LineMark(
                    x: .value("Time", data.time),
                    y: .value("Wind Speed (mph)", data.windSpeed * 5)
                )
                .foregroundStyle(by: .value("Metric", "Wind Speed (mph)"))
            }
            
            ForEach(filteredData) { data in
                LineMark(
                    x: .value("Time", data.time),
                    y: .value("Precipitation (%)", data.precipitationProbability)
                )
                .foregroundStyle(by: .value("Metric", "Precipitation (%)"))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 3600)) { value in
                if let date = value.as(Date.self) {
                    let hour = Calendar.current.component(.hour, from: date)
                    if hour >= 5 && hour <= 21 {
                        AxisGridLine()
                        AxisValueLabel {
                            Text("\(hour):00")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            // Temperature axis (left)
            AxisMarks(position: .leading, values: .stride(by: 25)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let temp = value.as(Double.self) {
                        Text("\(Int(temp))°F")
                            .foregroundColor(.red)
                            .padding(.trailing, -4)
                    }
                }
            }
            
            // Percentage axis (right)
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        HStack(spacing: 2) {
                            Text("\(Int(val))")
                            Text("%")
                        }
                        .foregroundColor(.secondary)
                        .padding(.leading, -4)
                    }
                }
                
                if value.index == 2 {
                    AxisValueLabel(anchor: .top) {
                        Text("Cloud Cover & Precipitation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(90))
                            .offset(x: 30)
                    }
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartLegend(position: .top)
        .chartForegroundStyleScale([
            "Temperature (°F)": .red,
            "Cloud Cover (%)": .blue,
            "Wind Speed (mph)": .green,
            "Precipitation (%)": .purple
        ])
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .padding(.horizontal, 8)
    }
    
} 