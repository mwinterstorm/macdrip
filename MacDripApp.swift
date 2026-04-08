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
            Text(monitor.menuBarTitle)
                .foregroundColor(monitor.glucoseColor)
        }
        .menuBarExtraStyle(.window)  
    }
}