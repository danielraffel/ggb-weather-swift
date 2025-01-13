import SwiftUI
import Inject

struct BestVisitTimeView: View {
    @ObserveInjection var inject
    let bestTimes: [BestVisitTime]
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Best Times to Visit")
                .font(.headline)
            
            HStack(spacing: 16) {
                if bestTimes.isEmpty {
                    Text("Loading best times...")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(bestTimes.enumerated()), id: \.element.time) { index, time in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(index == 0 ? "🥇 Best time" : "🥈 Second best")
                                    .font(.subheadline.bold())
                                    .foregroundColor(index == 0 ? .yellow : .gray)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("⏰ \(dateFormatter.string(from: time.time))")
                                Text("🌡️ \(time.temperature, specifier: "%.1f")°F")
                                Text("🌧 \(time.precipitationProbability, specifier: "%.0f")% chance")
                                Text("☁️ \(time.cloudCover, specifier: "%.0f")% cover")
                                Text("🌬️ \(time.windSpeed, specifier: "%.1f") mph")
                            }
                            .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .enableInjection()
    }
} 