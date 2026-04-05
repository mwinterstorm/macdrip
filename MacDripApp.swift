import SwiftUI
import AppKit
import CryptoKit

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

// --- 1. THE UI CONTROLLER ---
struct MacDripMenuView: View {
    @ObservedObject var monitor: GlucoseMonitor
    @State private var showingSettings = false
    
    @AppStorage("apiSecret") private var apiSecret = ""
    @AppStorage("manualIP") private var manualIP = ""
    @AppStorage("isAutoDiscover") private var isAutoDiscover = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferences")
                        .font(.headline)
                    
                    SecureField("API Secret (Plain Text)", text: $apiSecret)
                        .textFieldStyle(.roundedBorder)
                    
                    Divider()
                    
                    Toggle("Auto-Discover Phone on Network", isOn: $isAutoDiscover)
                    
                    if !isAutoDiscover {
                        TextField("Manual Phone IP", text: $manualIP)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text("Note: Auto-discover will scan the subnet based on your manual IP (e.g., \(manualIP.components(separatedBy: ".").dropLast().joined(separator: ".")).X).")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // FIXED: macOS 14+ modern syntax (no underscore)
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
                VStack(spacing: 12) {
                    Text("CURRENT GLUCOSE")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .tracking(1.5)
                    
                    Text(monitor.displayString)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    
                    if isAutoDiscover {
                        Text(monitor.isScanning ? "Scanning network..." : "Discovered: \(monitor.discoveredIP.isEmpty ? "Not Found" : monitor.discoveredIP)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        Text("Manual IP: \(manualIP)")
                            .font(.caption)
                            .foregroundColor(.gray)
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
        .frame(width: 300) 
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

// --- 2. THE DATA ENGINE ---
class GlucoseMonitor: ObservableObject {
    @Published var displayString: String = "Loading..."
    @Published var isScanning = false
    @Published var discoveredIP = ""
    
    var apiSecret: String { UserDefaults.standard.string(forKey: "apiSecret") ?? "" }
    var manualIP: String { UserDefaults.standard.string(forKey: "manualIP") ?? "" }
    var isAutoDiscover: Bool { UserDefaults.standard.bool(forKey: "isAutoDiscover") }
    
    var activeIP: String {
        return isAutoDiscover ? (discoveredIP.isEmpty ? manualIP : discoveredIP) : manualIP
    }
    
    init() {
        fetch()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.fetch() }
    }
    
    func startDiscovery() {
        guard !isScanning else { return }
        isScanning = true
        
        let components = manualIP.split(separator: ".")
        guard components.count == 4 else {
            isScanning = false
            return
        }
        let subnetBase = "\(components[0]).\(components[1]).\(components[2])"
        
        var foundIP: String? = nil
        let group = DispatchGroup()
        
        for i in 1...254 {
            let testIP = "\(subnetBase).\(i)"
            guard let url = URL(string: "http://\(testIP):17580/") else { continue }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 0.5
            
            group.enter()
            URLSession.shared.dataTask(with: request) { _, response, _ in
                // FIXED: Just check if it's an HTTP response, without assigning it to an unused variable
                if response is HTTPURLResponse {
                    if foundIP == nil { foundIP = testIP }
                }
                group.leave()
            }.resume()
        }
        
        group.notify(queue: .main) {
            self.isScanning = false
            if let targetIP = foundIP {
                self.discoveredIP = targetIP
                self.fetch()
            } else {
                self.displayString = "Scan Failed"
            }
        }
    }
    
    func sha1(_ input: String) -> String {
        let data = Data(input.utf8)
        return Insecure.SHA1.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func fetch() {
        if isAutoDiscover && discoveredIP.isEmpty && !isScanning {
            startDiscovery()
            return
        }
        
        guard let url = URL(string: "http://\(activeIP):17580/sgv.json?count=1") else { return }
        var request = URLRequest(url: url)
        request.setValue(sha1(apiSecret), forHTTPHeaderField: "api-secret")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                self.handleFailure(reason: "Net Error")
                return
            }
            guard let data = data else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let latest = json.first else {
                self.handleFailure(reason: "Auth Error")
                return
            }
            let rawSgv = latest["sgv"]
            guard let sgv = (rawSgv as? NSNumber)?.doubleValue ?? Double(String(describing: rawSgv ?? "")) else {
                self.handleFailure(reason: "SGV Error")
                return
            }
            
            let mmol = sgv / 18.018
            let direction = latest["direction"] as? String ?? ""
            
            DispatchQueue.main.async {
                self.displayString = String(format: "%.1f %@", mmol, self.arrow(direction))
            }
        }.resume()
    }
    
    func handleFailure(reason: String) {
        DispatchQueue.main.async {
            self.displayString = reason
            if self.isAutoDiscover && !self.isScanning {
                self.discoveredIP = ""
                self.startDiscovery()
            }
        }
    }
    
    func arrow(_ dir: String) -> String {
        let arrows = ["Flat": "→", "SingleUp": "↑", "DoubleUp": "↑↑", "FortyFiveUp": "↗", 
                      "FortyFiveDown": "↘", "SingleDown": "↓", "DoubleDown": "↓↓"]
        return arrows[dir] ?? "→"
    }
}