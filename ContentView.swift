import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var monitor: GlucoseMonitor
    
    @AppStorage("manualIP") private var manualIP = ""
    @AppStorage("showForecast") private var showForecast = false
    @AppStorage("lowThreshold") private var lowThreshold = 4.0
    
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
                .padding(.bottom, 20)
            
            // --- CHART ---
            let chartData = monitor.history.filter { $0.date >= Date().addingTimeInterval(-43200) } // 12 hours
            
            if !chartData.isEmpty {
                Chart(chartData) { point in
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
                }
                .frame(maxHeight: 300)
                .chartYScale(domain: monitor.yAxisBounds)
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
        .navigationTitle("History")
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
            
            Section(header: Text("System")) {
                Toggle("Launch automatically at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { toggleLaunchAtLogin() }
                    
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
            
            Section(header: Text("Database Expansion")) {
                VStack(alignment: .leading) {
                    Text("Deep-Sync Historical Data (Weeks)")
                    HStack {
                        Slider(value: $weeksToSync, in: 1...52, step: 1)
                        Text("\(Int(weeksToSync))")
                            .frame(width: 30)
                    }
                }
                
                Button(action: {
                    monitor.syncHistoricalData(weeks: Int(weeksToSync))
                }) {
                    HStack {
                        Text("Start Background Sync")
                        Spacer()
                        if let status = monitor.syncStatus {
                            Text(status)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Text(String(format: "Local Database Size: %d readings", monitor.history.count))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 400)
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
