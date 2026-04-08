import Foundation
import SwiftUI
import CryptoKit

class GlucoseMonitor: ObservableObject {
    @Published var displayString: String = "Loading..."
    @Published var history: [GlucoseReading] = [] 
    @Published var isLowPredicted: Bool = false
    @Published var predictedGlucoseIn30: Double?
    @Published var isCompressionLow: Bool = false
    @Published var syncStatus: String?
    
    var menuBarTitle: String {
        if isCompressionLow {
            return "⚠️ COMPRESSION LOW"
        } else if isLowPredicted && !displayString.contains("Error") && !displayString.contains("Loading") {
            return "⚠️ LOW PREDICTED: \(displayString)"
        } else {
            return "🩸 \(displayString)"
        }
    } 
    
    var apiSecret: String { UserDefaults.standard.string(forKey: "apiSecret") ?? "" }
    var manualIP: String { UserDefaults.standard.string(forKey: "manualIP") ?? "" }
    var lowThreshold: Double { UserDefaults.standard.double(forKey: "lowThreshold") }
    var predictionMethod: String { UserDefaults.standard.string(forKey: "predictionMethod") ?? PredictionMethod.weightedSlope.rawValue }
    
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
    
    func yAxisBounds(for data: [GlucoseReading]) -> [Double] {
        guard !data.isEmpty else { return [3.0, 12.0] }
        let minG = data.map { $0.glucose }.min() ?? 3.0
        let maxG = data.map { $0.glucose }.max() ?? 12.0
        let dynamicMin = min(3.0, floor(minG))
        let ceilMax = ceil(maxG)
        let evenMax = Int(ceilMax) % 2 == 0 ? ceilMax : ceilMax + 1.0
        let dynamicMax = max(12.0, evenMax)
        return [dynamicMin, dynamicMax]
    }
    
    var fetchTimer: Timer?
    var hasPerformedInitialDeepFetch = false
    
    private var dataFileURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.macdrip.app", isDirectory: true)
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        }
        return appDir.appendingPathComponent("history.json")
    }
    
    init() {
        loadHistory()
        fetch()
    }
    
    func saveHistory() {
        // Offload large writes to a background thread conceptually, but we need memory safety. 
        // A simple atomic write is mostly instantaneous up to a few MBs.
        DispatchQueue.global(qos: .background).async {
            let copy = self.history
            if let data = try? JSONEncoder().encode(copy) {
                try? data.write(to: self.dataFileURL, options: .atomic)
            }
        }
    }
    
    func loadHistory() {
        // Migration from legacy UserDefaults if standard file doesn't exist yet
        if !FileManager.default.fileExists(atPath: dataFileURL.path),
           let oldData = UserDefaults.standard.data(forKey: "glucoseHistoryJSON"),
           let decoded = try? JSONDecoder().decode([GlucoseReading].self, from: oldData) {
            self.history = decoded
            saveHistory()
            return
        }
        
        if let data = try? Data(contentsOf: dataFileURL),
           let decoded = try? JSONDecoder().decode([GlucoseReading].self, from: data) {
            self.history = decoded
        }
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
    
    private func parseJSON(jsonArray: [[String: Any]]) -> [GlucoseReading] {
        var incomingData: [GlucoseReading] = []
        for item in jsonArray {
            if let rawSgv = item["sgv"],
               let sgv = (rawSgv as? NSNumber)?.doubleValue ?? Double(String(describing: rawSgv)),
               let timeMs = item["date"] as? Double {
                let mmol = sgv / 18.018
                let date = Date(timeIntervalSince1970: timeMs / 1000.0)
                
                let direction = item["direction"] as? String
                let trend = item["trend"] as? Int
                let device = item["device"] as? String
                let type = item["type"] as? String
                let noise = item["noise"] as? Int
                let filtered = (item["filtered"] as? NSNumber)?.doubleValue ?? Double(String(describing: item["filtered"] ?? "")) 
                let unfiltered = (item["unfiltered"] as? NSNumber)?.doubleValue ?? Double(String(describing: item["unfiltered"] ?? ""))
                let rssi = item["rssi"] as? Int
                let sysTime = item["sysTime"] as? String ?? item["dateString"] as? String
                
                incomingData.append(GlucoseReading(
                    timestamp: timeMs, date: date, glucose: mmol,
                    sgv: sgv, direction: direction, trend: trend,
                    device: device, type: type, noise: noise,
                    filtered: filtered, unfiltered: unfiltered, rssi: rssi, sysTime: sysTime
                ))
            }
        }
        return incomingData
    }
    
    func fetch() {
        fetchTimer?.invalidate()
        let fetchCount = self.hasPerformedInitialDeepFetch ? 36 : 1000
        
        guard let url = URL(string: "http://\(manualIP):17580/sgv.json?count=\(fetchCount)") else { 
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
            
            let incomingData = self.parseJSON(jsonArray: jsonArray)
            
            DispatchQueue.main.async {
                self.hasPerformedInitialDeepFetch = true
                var existingDict = [Double: GlucoseReading]()
                for reading in self.history { existingDict[reading.timestamp] = reading }
                for reading in incomingData { existingDict[reading.timestamp] = reading }
                
                var merged = Array(existingDict.values)
                merged.sort { $0.date < $1.date }
                
                // Infinite DB: We DO NOT filter by cutoff date anymore!
                
                self.history = merged
                self.saveHistory()
                
                if let latest = self.history.last, let latestJson = jsonArray.first {
                    let ageSeconds = Int(Date().timeIntervalSince(latest.date))
                    let ageMinutes = ageSeconds / 60
                    let direction = latestJson["direction"] as? String ?? ""
                    
                    if ageMinutes >= 15 {
                        self.displayString = String(format: "⏳ %.1f (Stale)", latest.glucose)
                    } else {
                        self.displayString = String(format: "%.1f %@", latest.glucose, self.arrow(direction))
                    }
                    self.checkPredictions()
                } else {
                    self.displayString = "SGV Error"
                }
                
                self.scheduleNextFetch()
            }
        }.resume()
    }
    
    // --- HISTORICAL PAGINATION ---
    func syncHistoricalData(weeks: Int) {
        let totalItems = weeks * 2016 // 7 days * 288 points
        syncStatus = "Starting massive deep sync..."
        
        let urlString = "http://\(manualIP):17580/sgv.json?count=\(totalItems)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.setValue(sha1(apiSecret), forHTTPHeaderField: "api-secret")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !jsonArray.isEmpty else {
                DispatchQueue.main.async {
                    self.syncStatus = "Sync failed or empty API."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.syncStatus = nil }
                }
                return
            }
            
            let incomingData = self.parseJSON(jsonArray: jsonArray)
            
            DispatchQueue.main.async {
                var existingDict = [Double: GlucoseReading]()
                for reading in self.history { existingDict[reading.timestamp] = reading }
                for reading in incomingData { existingDict[reading.timestamp] = reading }
                var merged = Array(existingDict.values)
                merged.sort { $0.date < $1.date }
                
                self.history = merged
                self.saveHistory() 
                
                self.syncStatus = "Sync Complete! Recovered \(jsonArray.count) records."
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.syncStatus = nil }
            }
        }.resume()
    }
    
    // --- PREDICTION ENGINE ---
    func calculateWeightedRate() -> Double {
        guard history.count >= 5 else { 
            if history.count >= 2 {
                let pCurrent = history.last!
                let pPast = history[history.count - 2]
                let dt = max(1.0, pCurrent.date.timeIntervalSince(pPast.date) / 60.0)
                return (pCurrent.glucose - pPast.glucose) / dt
            }
            return 0.0 
        }
        let weights: [Double] = [1.5, 1.2, 1.0, 0.8] 
        var totalWeightedRate = 0.0
        var weightSum = 0.0
        for i in 0..<4 {
            let index = history.count - 1 - i
            let pCurrent = history[index]
            let pPast = history[index - 1]
            let dt = max(1.0, pCurrent.date.timeIntervalSince(pPast.date) / 60.0)
            let rate = (pCurrent.glucose - pPast.glucose) / dt
            totalWeightedRate += (rate * weights[i])
            weightSum += weights[i]
        }
        return totalWeightedRate / weightSum
    }

    func checkPredictions() {
        guard history.count >= 4 else { return }
        let current = history.last!
        let past = history[history.count - 4] 
        let timeDiffMinutes = current.date.timeIntervalSince(past.date) / 60.0
        guard timeDiffMinutes > 0 else { return }
        
        var dropRatePerMinute: Double = 0.0
        let method = PredictionMethod(rawValue: predictionMethod) ?? .weightedSlope
        
        if method == .linear {
            dropRatePerMinute = (current.glucose - past.glucose) / timeDiffMinutes
        } else if method == .emaSmoothed {
            var ema = 0.0
            let alpha = 0.3 
            var first = true
            for i in 1..<history.count {
                let p1 = history[i-1]
                let p2 = history[i]
                let dt = max(1.0, p2.date.timeIntervalSince(p1.date) / 60.0)
                let rate = (p2.glucose - p1.glucose) / dt
                if first {
                    ema = rate; first = false
                } else {
                    ema = (alpha * rate) + ((1.0 - alpha) * ema)
                }
            }
            dropRatePerMinute = ema
        } else {
            dropRatePerMinute = calculateWeightedRate()
        }
        
        if dropRatePerMinute < -1.0 {
            self.isCompressionLow = true
            self.isLowPredicted = false
            self.predictedGlucoseIn30 = nil
            return
        }
        
        let predictedIn30 = current.glucose + (dropRatePerMinute * 30.0)
        let threshold = lowThreshold == 0 ? 4.0 : lowThreshold 
        let isLow = predictedIn30 <= threshold && dropRatePerMinute < -0.02
        
        self.isCompressionLow = false
        self.isLowPredicted = isLow
        self.predictedGlucoseIn30 = predictedIn30
        
        if isLow {
            if let lastAlert = lastAlertTime, Date().timeIntervalSince(lastAlert) < 1800 { return }
            triggerNotification(current: current.glucose, predicted: predictedIn30)
            lastAlertTime = Date()
        }
    }
    
    func triggerNotification(current: Double, predicted: Double) {
        let message = String(format: "Currently %.1f and dropping. Predicted to hit %.1f in 30 minutes.", current, predicted)
        let script = "display notification \"\(message)\" with title \"🩸 Upcoming Low Warning\""
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) { appleScript.executeAndReturnError(&error) }
    }
    
    func arrow(_ dir: String) -> String {
        let arrows = ["Flat": "→", "SingleUp": "↑", "DoubleUp": "↑↑", "FortyFiveUp": "↗", 
                      "FortyFiveDown": "↘", "SingleDown": "↓", "DoubleDown": "↓↓"]
        return arrows[dir] ?? "→"
    }
}
