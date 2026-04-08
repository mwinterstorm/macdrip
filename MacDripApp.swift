import SwiftUI
import AppKit
import Charts

let appVersion = "2.0.0"

@main
struct MacDripApp: App {
    @StateObject private var monitor = GlucoseMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
        }
        
        MenuBarExtra {
            MiniDashboardView(monitor: monitor)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: monitor.isCompressionLow ? "exclamationmark.triangle.fill" : "drop.fill")
                Text(monitor.menuBarTitle)
            }
            .foregroundColor(monitor.glucoseColor)
        }
        .menuBarExtraStyle(.window)  
    }
}