import SwiftUI
import Charts

struct MiniDashboardView: View {
    @ObservedObject var monitor: GlucoseMonitor
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                Text(monitor.displayString)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(monitor.glucoseColor)
                if let change = monitor.changeFromLastTimeString {
                    Text(change)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
            }
            
            if let lastDate = monitor.history.last?.date {
                let minutesAgo = max(0, Int(Date().timeIntervalSince(lastDate) / 60.0))
                Text("\(lastDate.formatted(date: .omitted, time: .shortened)) (\(minutesAgo) min ago)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            if monitor.isCompressionLow {
                Text("⚠️ Compression Low Detected")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
            } else if UserDefaults.standard.bool(forKey: "showForecast"), let predicted = monitor.predictedGlucoseIn30 {
                Text(String(format: "30m Forecast: %.1f", predicted))
                    .font(.caption)
                    .foregroundColor(monitor.isLowPredicted ? .red : .blue)
            }
            
            // 3-hour chart
            let chartData = monitor.history.filter { $0.date >= Date().addingTimeInterval(-10800) }
            if !chartData.isEmpty {
                Chart(chartData) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Glucose", point.glucose))
                        .foregroundStyle(Color.blue.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Time", point.date), y: .value("Glucose", point.glucose))
                        .foregroundStyle(Color.blue)
                        .symbolSize(30)
                }
                .frame(height: 120)
                .chartYScale(domain: monitor.yAxisBounds(for: chartData))
            } else {
                Text("No data available")
                    .foregroundColor(.gray)
                    .frame(height: 120)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            HStack {
                Button("Refresh") { monitor.fetch() }
                Spacer()
                Button("Open App") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .bold()
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            .font(.callout)
        }
        .padding()
        .frame(width: 300)
    }
}
