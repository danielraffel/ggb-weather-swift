import SwiftUI
import Charts

struct WeatherChartView: View {
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Weather Forecast")
                .font(.headline)
            
            if #available(iOS 16.0, *) {
                VStack(alignment: .leading, spacing: 4) {
                    // Chart Title with scales
                    HStack(spacing: 16) {
                        Text("Temperature (°F)")
                            .foregroundColor(.red)
                        Text("Cloud Cover (%)")
                            .foregroundColor(.blue)
                        Text("Wind Speed (mph)")
                            .foregroundColor(.green)
                        Text("Precipitation (%)")
                            .foregroundColor(.purple)
                    }
                    .font(.caption)
                    
                    chartView
                }
            } else {
                Text("Charts require iOS 16.0 or later")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @available(iOS 16.0, *)
    private var chartView: some View {
        Chart {
            ForEach(filteredData) { data in
                LineMark(
                    x: .value("Time", data.time),
                    y: .value("Temperature", data.temperature)
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(by: .value("Metric", "Temperature"))
            }
            
            ForEach(filteredData) { data in
                LineMark(
                    x: .value("Time", data.time),
                    y: .value("Cloud Cover", data.cloudCover)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(by: .value("Metric", "Cloud Cover"))
            }
            
            ForEach(filteredData) { data in
                LineMark(
                    x: .value("Time", data.time),
                    y: .value("Wind Speed", data.windSpeed)
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(by: .value("Metric", "Wind Speed"))
            }
            
            ForEach(filteredData) { data in
                LineMark(
                    x: .value("Time", data.time),
                    y: .value("Precipitation", data.precipitationProbability)
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(by: .value("Metric", "Precipitation"))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 3600)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(dateFormatter.string(from: date))
                            .font(.caption)
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                }
            }
        }
        .chartYAxis {
            AxisMarks(preset: .automatic, position: .leading)
        }
        .chartLegend(position: .top)
        .chartForegroundStyleScale([
            "Temperature": .red,
            "Cloud Cover": .blue,
            "Wind Speed": .green,
            "Precipitation": .purple
        ])
        .frame(height: 300)
        .padding(.top, 8)
    }
} 