import Foundation
import SwiftUI
import CryptoKit

class GlucoseMonitor: ObservableObject {
    @Published var displayString: String = "Loading..."
    @Published var history: [GlucoseReading] = [] 
    @Published var isLowPredicted: Bool = false
    @Published var predictedGlucoseIn30: Double?
    @Published var isCompressionLow: Bool = false
    
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
        loadHistory()
        fetch()
    }
    
    func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "glucoseHistoryJSON")
        }
    }
    
    func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "glucoseHistoryJSON"),
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
    
    func fetch() {
        fetchTimer?.invalidate()
        
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
            
            DispatchQueue.main.async {
                // Merge data using timestamp as unique key
                var existingDict = [Double: GlucoseReading]()
                for reading in self.history { existingDict[reading.timestamp] = reading }
                for reading in incomingData { existingDict[reading.timestamp] = reading }
                
                var merged = Array(existingDict.values)
                merged.sort { $0.date < $1.date }
                
                // Keep the last 48 hours to prevent JSON bloat, giving us huge history without SQLite
                let cutoff = Date().addingTimeInterval(-172800)
                merged = merged.filter { $0.date >= cutoff }
                
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
