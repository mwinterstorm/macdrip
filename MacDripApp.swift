import SwiftUI
import AppKit
import CryptoKit
import Charts

// Change this version string to easily update the version number shown in the app
let appVersion = "1.2.0"

@main
struct MacDripApp: App {
    @StateObject private var monitor = GlucoseMonitor()
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MacDripMenuView(monitor: monitor)
        } label: {
            Text(monitor.menuBarTitle)
                .foregroundColor(monitor.glucoseColor)
        }
        .menuBarExtraStyle(.window) 
    }
}

// --- A structure to hold each point on the graph ---
struct GlucosePoint: Identifiable {
    let id = UUID()
    let date: Date
    let glucose: Double
}

enum PredictionMethod: String, CaseIterable, Identifiable {
    case linear = "Linear (Classic)"
    case emaSmoothed = "EMA Smoothed"
    var id: Self { self }
}

// --- 1. THE UI CONTROLLER ---
struct MacDripMenuView: View {
    @ObservedObject var monitor: GlucoseMonitor
    @State private var showingSettings = false
    
    @AppStorage("apiSecret") private var apiSecret = ""
    @AppStorage("manualIP") private var manualIP = ""
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("lowThreshold") private var lowThreshold = 4.0
    @AppStorage("predictionMethod") private var predictionMethod: PredictionMethod = .emaSmoothed
    @AppStorage("showForecast") private var showForecast = false

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                // --- SETTINGS VIEW ---
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferences")
                        .font(.headline)
                    
                    SecureField("API Secret (Plain Text)", text: $apiSecret)
                        .textFieldStyle(.roundedBorder)
                    
                    Divider()
                    
                    TextField("Phone IP Address", text: $manualIP)
                        .textFieldStyle(.roundedBorder)
                    
                    // Settings UI for the predictive alert
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Predictive Low Alert Threshold (mmol/L):")
                            .font(.caption)
                        TextField("e.g. 4.0", value: $lowThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            
                        Picker("Prediction Method", selection: $predictionMethod) {
                            ForEach(PredictionMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Toggle("Show 30-min Forecast on Dashboard", isOn: $showForecast)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                    
                    Divider()
                    
                    Toggle("Launch automatically at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { toggleLaunchAtLogin() }
                    
                    HStack {
                        Text("MacDrip v\(appVersion)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Button("Save & Return") {
                            showingSettings = false
                            monitor.fetch() 
                        }
                        .keyboardShortcut(.defaultAction) 
                    }
                }
                .padding()
                
            } else {
                // --- MAIN DASHBOARD VIEW ---
                VStack(spacing: 12) {
                    Text("CURRENT GLUCOSE")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .tracking(1.5)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(monitor.displayString)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(monitor.glucoseColor)
                        
                        if let change = monitor.changeFromLastTimeString {
                            Text(change)
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if let lastDate = monitor.history.last?.date {
                        let minutesAgo = max(0, Int(Date().timeIntervalSince(lastDate) / 60.0))
                        Text("\(lastDate.formatted(date: .omitted, time: .shortened)) (\(minutesAgo) min ago)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    if showForecast, let predicted = monitor.predictedGlucoseIn30 {
                        Text(String(format: "30m Forecast: %.1f", predicted))
                            .font(.caption)
                            .foregroundColor(monitor.isLowPredicted ? .red : .blue)
                    }
                    
                    Text("Target: \(manualIP)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    // --- CHART ---
                    if !monitor.history.isEmpty {
                        Chart(monitor.history) { point in
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
                        .frame(height: 120)
                        .chartYScale(domain: monitor.yAxisBounds)
                        .padding(.top, 10)
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack {
                        Button("Refresh") { monitor.fetch() }
                        Spacer()
                        Button("Settings") { showingSettings = true }
                        Spacer()
                        Button("Quit") { NSApplication.shared.terminate(nil) }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
                .padding()
            }
        }
        .frame(width: 320) 
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

// --- 2. DATA ENGINE ---
class GlucoseMonitor: ObservableObject {
    @Published var displayString: String = "Loading..."
    @Published var history: [GlucosePoint] = [] 
    @Published var isLowPredicted: Bool = false
    @Published var predictedGlucoseIn30: Double?
    
    var menuBarTitle: String {
        if isLowPredicted && !displayString.contains("Error") && !displayString.contains("Loading") {
            return "⚠️ LOW PREDICTED: \(displayString)"
        } else {
            return "🩸 \(displayString)"
        }
    } 
    
    var apiSecret: String { UserDefaults.standard.string(forKey: "apiSecret") ?? "" }
    var manualIP: String { UserDefaults.standard.string(forKey: "manualIP") ?? "" }
    var lowThreshold: Double { UserDefaults.standard.double(forKey: "lowThreshold") }
    var predictionMethod: String { UserDefaults.standard.string(forKey: "predictionMethod") ?? PredictionMethod.emaSmoothed.rawValue }
    
    var lastAlertTime: Date?
    
    var changeFromLastTimeString: String? {
        guard history.count >= 2 else { return nil }
        let current = history[history.count - 1].glucose
        let previous = history[history.count - 2].glucose
        let difference = current - previous
        
        return difference == 0 ? "0.0" : String(format: "%+.1f", difference)
    }
    
    var glucoseColor: Color {
        guard let latest = history.last?.glucose else { return .primary }
        if latest > 15.0 {
            return .red
        } else if latest > 10.0 {
            return .orange
        } else if latest < 4.0 {
            return .blue
        } else {
            return .primary
        }
    }
    
    var yAxisBounds: [Double] {
        guard !history.isEmpty else { return [3.0, 12.0] }
        let minG = history.map { $0.glucose }.min() ?? 3.0
        let maxG = history.map { $0.glucose }.max() ?? 12.0
        let dynamicMin = min(3.0, floor(minG))
        let ceilMax = ceil(maxG)
        let evenMax = Int(ceilMax) % 2 == 0 ? ceilMax : ceilMax + 1.0
        let dynamicMax = max(12.0, evenMax)
        return [dynamicMin, dynamicMax]
    }
    
    var fetchTimer: Timer?
    
    init() {
        fetch()
    }
    
    func scheduleNextFetch() {
        fetchTimer?.invalidate()
        
        let delay: TimeInterval
        if let lastDate = history.last?.date {
            let timeSinceLast = Date().timeIntervalSince(lastDate)
            if timeSinceLast >= 300 {
                delay = 2.2
            } else {
                delay = 300.0 - timeSinceLast + 2.2
            }
        } else {
            delay = 10.0
        }
        
        fetchTimer = Timer.scheduledTimer(withTimeInterval: max(1.0, delay), repeats: false) { [weak self] _ in
            self?.fetch()
        }
    }
    
    func sha1(_ input: String) -> String {
        let data = Data(input.utf8)
        return Insecure.SHA1.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func fetch() {
        fetchTimer?.invalidate()
        let oldLatestDate = self.history.last?.date
        
        guard let url = URL(string: "http://\(manualIP):17580/sgv.json?count=36") else { 
            scheduleNextFetch()
            return 
        }
        
        print("Fetching data at \(Date().formatted(date: .omitted, time: .standard))...")
        
        var request = URLRequest(url: url)
        request.setValue(sha1(apiSecret), forHTTPHeaderField: "api-secret")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                DispatchQueue.main.async { 
                    self.displayString = "Net Error"
                    self.scheduleNextFetch()
                }
                return
            }
            guard let data = data else { 
                DispatchQueue.main.async { self.scheduleNextFetch() }
                return 
            }
            guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { 
                    self.displayString = "Auth Error"
                    self.scheduleNextFetch()
                }
                return
            }
            
            var newHistory: [GlucosePoint] = []
            
            for item in jsonArray {
                if let rawSgv = item["sgv"],
                   let sgv = (rawSgv as? NSNumber)?.doubleValue ?? Double(String(describing: rawSgv)),
                   let timeMs = item["date"] as? Double {
                    
                    let mmol = sgv / 18.018
                    let date = Date(timeIntervalSince1970: timeMs / 1000.0)
                    newHistory.append(GlucosePoint(date: date, glucose: mmol))
                }
            }
            
            newHistory.sort { $0.date < $1.date }
            
            DispatchQueue.main.async {
                self.history = newHistory
                
                if let latest = newHistory.last, let latestJson = jsonArray.first {
                    let ageSeconds = Int(Date().timeIntervalSince(latest.date))
                    let ageMinutes = ageSeconds / 60
                    
                    let direction = latestJson["direction"] as? String ?? ""
                    if ageMinutes >= 15 {
                        self.displayString = String(format: "⏳ %.1f (Stale)", latest.glucose)
                    } else {
                        self.displayString = String(format: "%.1f %@", latest.glucose, self.arrow(direction))
                    }
                    
                    if let old = oldLatestDate {
                        if latest.date > old {
                            print("✅ Received new data! Data is \(ageMinutes) min \(ageSeconds % 60) sec old.")
                        } else {
                            print("⏳ No new data yet. (Latest is \(ageMinutes) min \(ageSeconds % 60) sec old)")
                        }
                    } else {
                        print("✅ Received initial data! Data is \(ageMinutes) min \(ageSeconds % 60) sec old.")
                    }
                    
                    self.checkPredictions()
                } else {
                    self.displayString = "SGV Error"
                }
                
                self.scheduleNextFetch()
            }
        }.resume()
    }
    
    // --- PREDICTION ENGINE ---
    func checkPredictions() {
        guard history.count >= 4 else { return }
        
        let current = history.last!
        let past = history[history.count - 4] 
        
        let timeDiffMinutes = current.date.timeIntervalSince(past.date) / 60.0
        guard timeDiffMinutes > 0 else { return }
        
        var dropRatePerMinute: Double = 0.0
        let method = PredictionMethod(rawValue: predictionMethod) ?? .emaSmoothed
        
        if method == .linear {
            dropRatePerMinute = (current.glucose - past.glucose) / timeDiffMinutes
        } else {
            var ema = 0.0
            let alpha = 0.3 // Smoothing factor
            var first = true
            
            for i in 1..<history.count {
                let p1 = history[i-1]
                let p2 = history[i]
                let dt = max(1.0, p2.date.timeIntervalSince(p1.date) / 60.0)
                let rate = (p2.glucose - p1.glucose) / dt
                
                if first {
                    ema = rate
                    first = false
                } else {
                    ema = (alpha * rate) + ((1.0 - alpha) * ema)
                }
            }
            dropRatePerMinute = ema
        }
        
        let predictedIn30 = current.glucose + (dropRatePerMinute * 30.0)
        
        // Trigger conditions:
        // 1. Prediction crosses user threshold
        // 2. The blood sugar is actively dropping (dropRate is negative)
        // 3. Current glucose isn't super high (we don't care if dropping from 14 to 8)
        let threshold = lowThreshold == 0 ? 4.0 : lowThreshold // Failsafe for 0
        let isLow = predictedIn30 <= threshold && dropRatePerMinute < -0.02 && current.glucose < 7.0
        
        DispatchQueue.main.async {
            self.isLowPredicted = isLow
            self.predictedGlucoseIn30 = predictedIn30
        }
        
        if isLow {
            if let lastAlert = lastAlertTime, Date().timeIntervalSince(lastAlert) < 1800 {
                return 
            }
            triggerNotification(current: current.glucose, predicted: predictedIn30)
            lastAlertTime = Date()
        }
    }
    
    func triggerNotification(current: Double, predicted: Double) {
        let message = String(format: "Currently %.1f and dropping. Predicted to hit %.1f in 30 minutes.", current, predicted)
        let script = "display notification \"\(message)\" with title \"🩸 Upcoming Low Warning\""
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let err = error {
                print("Notification Error: \(err)")
            }
        }
    }
    // ----------------------------------
    
    func arrow(_ dir: String) -> String {
        let arrows = ["Flat": "→", "SingleUp": "↑", "DoubleUp": "↑↑", "FortyFiveUp": "↗", 
                      "FortyFiveDown": "↘", "SingleDown": "↓", "DoubleDown": "↓↓"]
        return arrows[dir] ?? "→"
    }
}