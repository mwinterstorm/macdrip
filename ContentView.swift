import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var monitor: GlucoseMonitor
    
    @AppStorage("manualIP") private var manualIP = ""
    @AppStorage("showForecast") private var showForecast = false
    @AppStorage("lowThreshold") private var lowThreshold = 4.0
    @AppStorage("chartHours") private var chartHours = 12
    
    @State private var hoveredReading: GlucoseReading?
    
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("Dashboard") {
                    dashboardView
                }
                NavigationLink("History") {
                    historyView
                }
                NavigationLink("Settings") {
                    SettingsView(monitor: monitor)
                }
            }
            .navigationTitle("MacDrip")
            .listStyle(.sidebar)
        } detail: {
            dashboardView // Default detail
        }
    }
    
    private var dashboardView: some View {
        VStack(spacing: 12) {
            Text("CURRENT GLUCOSE")
                .font(.headline)
                .foregroundColor(.gray)
                .tracking(1.5)
            
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(monitor.displayString)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(monitor.glucoseColor)
                
                if let change = monitor.changeFromLastTimeString {
                    Text(change)
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
            }
            
            if let lastDate = monitor.history.last?.date {
                let minutesAgo = max(0, Int(Date().timeIntervalSince(lastDate) / 60.0))
                Text("\(lastDate.formatted(date: .omitted, time: .shortened)) (\(minutesAgo) min ago)")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            
            if monitor.isCompressionLow {
                Text("⚠️ Compression Low Detected")
                    .font(.headline)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
                    .padding(.top, 4)
            } else if showForecast, let predicted = monitor.predictedGlucoseIn30 {
                Text(String(format: "30m Forecast: %.1f", predicted))
                    .font(.headline)
                    .foregroundColor(monitor.isLowPredicted ? .red : .blue)
            }
            
            Text("Target: \(manualIP)")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 10)
            
            // --- CHART TIME SCALE PICKER ---
            Picker("Time Range", selection: $chartHours) {
                Text("3h").tag(3)
                Text("6h").tag(6)
                Text("12h").tag(12)
                Text("24h").tag(24)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            
            // --- CHART ---
            let chartSeconds = Double(chartHours) * 3600.0
            let chartData = monitor.history.filter { $0.date >= Date().addingTimeInterval(-chartSeconds) }
            
            if !chartData.isEmpty {
                Chart {
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Glucose", point.glucose)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        
                        PointMark(
                            x: .value("Time", point.date),
                            y: .value("Glucose", point.glucose)
                        )
                        .foregroundStyle(Color.blue)
                        .symbolSize(20)
                    }
                    
                    // Hover tooltip rule + annotation
                    if let hovered = hoveredReading {
                        RuleMark(x: .value("Hovered", hovered.date))
                            .foregroundStyle(Color.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .center) {
                                VStack(spacing: 2) {
                                    Text(hovered.date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        Text(String(format: "%.1f", hovered.glucose))
                                            .font(.caption)
                                            .bold()
                                        if let dir = hovered.direction {
                                            Text(monitor.arrow(dir))
                                                .font(.caption)
                                        }
                                    }
                                }
                                .padding(6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            }
                    }
                }
                .frame(maxHeight: 300)
                .chartYScale(domain: monitor.yAxisBounds(for: chartData))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let plotFrame = geometry[proxy.plotFrame!]
                                    let relativeX = location.x - plotFrame.origin.x
                                    guard let hoveredDate: Date = proxy.value(atX: relativeX) else {
                                        hoveredReading = nil
                                        return
                                    }
                                    // Find nearest data point
                                    hoveredReading = chartData.min(by: {
                                        abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate))
                                    })
                                case .ended:
                                    hoveredReading = nil
                                }
                            }
                    }
                }
                .padding()
            } else {
                Text("No data available yet.")
                    .foregroundColor(.gray)
                    .frame(maxHeight: 300)
            }
            
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private var historyView: some View {
        VStack(spacing: 0) {
            // --- TIME IN RANGE ---
            tirStatsView
                .padding()
            
            Divider()
            
            List(monitor.history.reversed()) { reading in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(reading.date.formatted(date: .abbreviated, time: .standard))
                            .fontWeight(.medium)
                        Spacer()
                        if let direction = reading.direction {
                            Text(monitor.arrow(direction))
                                .foregroundColor(.gray)
                        }
                        Text(String(format: "%.1f", reading.glucose))
                            .bold()
                    }
                    
                    let metadata: [String] = [
                        reading.device != nil ? "Device: \(reading.device!)" : nil,
                        reading.noise != nil ? "Noise: \(reading.noise!)" : nil,
                        reading.rssi != nil ? "RSSI: \(reading.rssi!)" : nil,
                        reading.sysTime != nil ? "Time: \(reading.sysTime!)" : nil
                    ].compactMap { $0 }
                    
                    if !metadata.isEmpty {
                        Text(metadata.joined(separator: " • "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("History")
    }
    
    private var tirStatsView: some View {
        let tirLow = UserDefaults.standard.double(forKey: "tirLowThreshold")
        let tirHigh = UserDefaults.standard.double(forKey: "tirHighThreshold")
        let lowThresh = tirLow == 0 ? 3.9 : tirLow
        let highThresh = tirHigh == 0 ? 10.0 : tirHigh
        
        let last24h = monitor.history.filter { $0.date >= Date().addingTimeInterval(-86400) }
        let total = Double(last24h.count)
        
        let lowCount = Double(last24h.filter { $0.glucose < lowThresh }.count)
        let highCount = Double(last24h.filter { $0.glucose > highThresh }.count)
        let inRangeCount = total - lowCount - highCount
        
        let lowPct = total > 0 ? (lowCount / total) * 100.0 : 0
        let inRangePct = total > 0 ? (inRangeCount / total) * 100.0 : 0
        let highPct = total > 0 ? (highCount / total) * 100.0 : 0
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("📊 Time in Range (Last 24h)")
                .font(.headline)
            
            if total > 0 {
                // Stacked bar
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        if lowPct > 0 {
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geo.size.width * CGFloat(lowPct / 100.0))
                        }
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(inRangePct / 100.0))
                        if highPct > 0 {
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: geo.size.width * CGFloat(highPct / 100.0))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 20)
                
                HStack(spacing: 16) {
                    Label(String(format: "Low: %.0f%%", lowPct), systemImage: "circle.fill")
                        .foregroundColor(.blue)
                    Label(String(format: "In Range: %.0f%%", inRangePct), systemImage: "circle.fill")
                        .foregroundColor(.green)
                    Label(String(format: "High: %.0f%%", highPct), systemImage: "circle.fill")
                        .foregroundColor(.orange)
                }
                .font(.caption)
                
                Text("Based on \(Int(total)) readings  •  Range: \(String(format: "%.1f", lowThresh))–\(String(format: "%.1f", highThresh)) mmol/L")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("No data in the last 24 hours.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: GlucoseMonitor
    
    @AppStorage("apiSecret") private var apiSecret = ""
    @AppStorage("manualIP") private var manualIP = ""
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("lowThreshold") private var lowThreshold = 4.0
    @AppStorage("predictionMethod") private var predictionMethod: PredictionMethod = .weightedSlope
    @AppStorage("showForecast") private var showForecast = false
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("tirLowThreshold") private var tirLowThreshold = 3.9
    @AppStorage("tirHighThreshold") private var tirHighThreshold = 10.0

    @State private var weeksToSync: Double = 4.0

    var body: some View {
        Form {
            Section(header: Text("Network Settings")) {
                SecureField("API Secret (Plain Text)", text: $apiSecret)
                    .textFieldStyle(.roundedBorder)
                TextField("Phone IP Address", text: $manualIP)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section(header: Text("Predictive Alerts")) {
                TextField("Low Alert Threshold (mmol/L):", value: $lowThreshold, format: .number)
                    .textFieldStyle(.roundedBorder)
                    
                Picker("Prediction Method", selection: $predictionMethod) {
                    ForEach(PredictionMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.menu)
                
                Toggle("Show 30-min Forecast on Dashboard", isOn: $showForecast)
            }
            
            Section(header: Text("Time in Range")) {
                TextField("Low Threshold (mmol/L):", value: $tirLowThreshold, format: .number)
                    .textFieldStyle(.roundedBorder)
                TextField("High Threshold (mmol/L):", value: $tirHighThreshold, format: .number)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section(header: Text("System")) {
                Toggle("Launch automatically at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { toggleLaunchAtLogin() }
                
                Toggle("Hide Dock icon (menu bar only)", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { applyDockIconVisibility() }
                    
                Button("Force Refresh") {
                    monitor.fetch()
                }
                
                HStack {
                    Spacer()
                    Text("MacDrip v\(appVersion)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.top, 10)
            }
            
        }
        .padding()
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 500)
    }
    
    func applyDockIconVisibility() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }
    
    func toggleLaunchAtLogin() {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.macdrip.app.plist")
        
        if !launchAtLogin {
            try? FileManager.default.removeItem(at: plistPath)
        } else {
            let execPath = Bundle.main.executableURL?.path ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
            let plistDict: [String: Any] = [
                "Label": "com.macdrip.app",
                "ProgramArguments": [execPath],
                "RunAtLoad": true
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0) {
                try? data.write(to: plistPath)
            }
        }
    }
}
