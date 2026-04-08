import SwiftUI
import AppKit
import Charts

let appVersion = "2.0.0"

class AppDelegate: NSObject, NSApplicationDelegate {
    // Force macOS to organically boot the AppKit UI lifecycle engine even on unsigned binaries!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "hideDockIcon") {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@main
struct MacDripApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = GlucoseMonitor()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(monitor: monitor)
        }
        
        MenuBarExtra(monitor.menuBarTitle, isInserted: .constant(true)) {
            MiniDashboardView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)  
    }
}