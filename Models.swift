import Foundation

struct GlucoseReading: Identifiable, Codable {
    var timestamp: Double
    var date: Date
    var glucose: Double
    
    var id: Double { timestamp }
    
    // Extended xDrip/Nightscout API fields
    var sgv: Double?
    var direction: String?
    var trend: Int?
    var device: String?
    var type: String?
    var noise: Int?
    var filtered: Double?
    var unfiltered: Double?
    var rssi: Int?
    var sysTime: String?
    
    init(timestamp: Double, date: Date, glucose: Double, 
         sgv: Double? = nil, direction: String? = nil, trend: Int? = nil, 
         device: String? = nil, type: String? = nil, noise: Int? = nil, 
         filtered: Double? = nil, unfiltered: Double? = nil, rssi: Int? = nil, sysTime: String? = nil) {
        self.timestamp = timestamp
        self.date = date
        self.glucose = glucose
        
        self.sgv = sgv
        self.direction = direction
        self.trend = trend
        self.device = device
        self.type = type
        self.noise = noise
        self.filtered = filtered
        self.unfiltered = unfiltered
        self.rssi = rssi
        self.sysTime = sysTime
    }
}

enum PredictionMethod: String, CaseIterable, Identifiable, Codable {
    case linear = "Linear (Classic)"
    case emaSmoothed = "EMA Smoothed"
    case weightedSlope = "Weighted Slope"
    var id: Self { self }
}
