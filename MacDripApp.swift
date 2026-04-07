import SwiftUI
import AppKit
import CryptoKit
import Charts 

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
            Text("🩸 \(monitor.displayString)")
        }
        .menuBarExtraStyle(.window) 
    }
}

// --- structure to hold each point on the graph ---
struct GlucosePoint: Identifiable {
    let id = UUID()
    let date: Date
    let glucose: Double
}

// --- 1. THE UI CONTROLLER ---
struct MacDripMenuView: View {
    @ObservedObject var monitor: GlucoseMonitor
    @State private var showingSettings = false
    
    @AppStorage("apiSecret") private var apiSecret = ""
    @AppStorage("manualIP") private var manualIP = "192.168.88.83"
    @AppStorage("launchAtLogin") private var launchAtLogin = false

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
                    
                    TextField("Phone IP Address (Local or Tailscale)", text: $manualIP)
                        .textFieldStyle(.roundedBorder)
                    
                    Divider()
                    
                    Toggle("Launch automatically at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { toggleLaunchAtLogin() }
                    
                    HStack {
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
                    
                    Text(monitor.displayString)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    
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
    @Published var history: [GlucosePoint] = [] // Array to hold graph data
    
    var apiSecret: String { UserDefaults.standard.string(forKey: "apiSecret") ?? "" }
    var manualIP: String { UserDefaults.standard.string(forKey: "manualIP") ?? "192.168.88.83" }
    
// --- Dynamic Graph Scaling Logic ---
    var yAxisBounds: [Double] {
        guard !history.isEmpty else { return [3.0, 12.0] }
        
        let minG = history.map { $0.glucose }.min() ?? 3.0
        let maxG = history.map { $0.glucose }.max() ?? 12.0
        
        // 1. Round down min value to nearest whole number (e.g., 2.8 -> 2.0)
        // Ensure the graph bottom never goes higher than 3.0
        let dynamicMin = min(3.0, floor(minG))
        
        // 2. Round up max value to nearest even whole number
        let ceilMax = ceil(maxG) // e.g., 14.1 -> 15.0
        let evenMax = Int(ceilMax) % 2 == 0 ? ceilMax : ceilMax + 1.0 // 15.0 -> 16.0
        
        // Ensure the graph top never goes lower than 12.0
        let dynamicMax = max(12.0, evenMax)
        
        return [dynamicMin, dynamicMax]
    }

    init() {
        fetch()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.fetch() }
    }
    
    func sha1(_ input: String) -> String {
        let data = Data(input.utf8)
        return Insecure.SHA1.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func fetch() {
        // Get last 36 records (3 hours of 5-minute data)
        guard let url = URL(string: "http://\(manualIP):17580/sgv.json?count=36") else { return }
        var request = URLRequest(url: url)
        request.setValue(sha1(apiSecret), forHTTPHeaderField: "api-secret")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                DispatchQueue.main.async { self.displayString = "Net Error" }
                return
            }
            guard let data = data else { return }
            guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { self.displayString = "Auth Error" }
                return
            }
            
            var newHistory: [GlucosePoint] = []
            
            // build the graph
            for item in jsonArray {
                if let rawSgv = item["sgv"],
                   let sgv = (rawSgv as? NSNumber)?.doubleValue ?? Double(String(describing: rawSgv)),
                   let timeMs = item["date"] as? Double { // xDrip sends time in milliseconds
                    
                    let mmol = sgv / 18.018
                    let date = Date(timeIntervalSince1970: timeMs / 1000.0)
                    newHistory.append(GlucosePoint(date: date, glucose: mmol))
                }
            }
            
            // Sort  chronologically (oldest to newest) 
            newHistory.sort { $0.date < $1.date }
            
            DispatchQueue.main.async {
                self.history = newHistory
                
                // Update the menu bar text with the most recent reading (the last one in our sorted list)
                if let latest = newHistory.last, let latestJson = jsonArray.first {
                    let direction = latestJson["direction"] as? String ?? ""
                    self.displayString = String(format: "%.1f %@", latest.glucose, self.arrow(direction))
                } else {
                    self.displayString = "SGV Error"
                }
            }
        }.resume()
    }
    
    func arrow(_ dir: String) -> String {
        let arrows = ["Flat": "→", "SingleUp": "↑", "DoubleUp": "↑↑", "FortyFiveUp": "↗", 
                      "FortyFiveDown": "↘", "SingleDown": "↓", "DoubleDown": "↓↓"]
        return arrows[dir] ?? "→"
    }
}