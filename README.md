# 🩸 MacDrip

A lightweight, native macOS application that displays real-time continuous glucose monitor (CGM) data directly from an Android phone running xDrip+.

Unlike standard setups that require bouncing medical data through a cloud-hosted Nightscout server, MacDrip connects to your phone directly over your local Wi-Fi network (or via Tailscale or similar VPNs). This results in instant updates, zero hosting costs, and complete data privacy.

## ✨ Features

### Live Monitoring
- **Menu Bar Display**: Shows your current glucose reading, trend arrow, and warnings directly in the macOS menu bar — always visible at a glance.
- **Mini Dashboard**: Click the menu bar text to see a compact popover with your current reading, change from last reading, time since last update, 30-minute forecast, and a 3-hour trend chart.
- **Full Dashboard**: A dedicated macOS window with a large glucose display, delta change, trend chart spanning the last 12 hours, and connection status.

### Predictive Alerts
- **Time-to-Low Prediction**: Uses advanced modelling algorithms to predict if your glucose will reach a critical low within 30 minutes. Three prediction methods are available:
  - **Weighted Slope** *(Default/Recommended)*: Heavily prioritises the most recent sensor reading while smoothing previous data, offering the best balance of speed and noise reduction.
  - **EMA Smoothed**: Uses an Exponential Moving Average to filter out noise and calculate the underlying direction.
  - **Linear (Classic)**: Strictly analyses the raw drop over the last 15 minutes. Highly sensitive but prone to false alarms.
- **Compression Low Detection**: Automatically flags unphysiological drops caused by sensor compression (e.g. sleeping on the sensor), preventing false panic alerts.
- **Native macOS Notifications**: When a valid low is predicted, the app sends a macOS notification and updates the menu bar to `⚠️ LOW PREDICTED`.
- **Dashboard Forecast**: Toggle on a 30-minute predicted value directly on the dashboard.

### Data & History
- **Persistent History**: All glucose readings are stored to disk in Application Support, surviving app restarts. Supports migration from legacy UserDefaults storage.
- **Historical Data Sync**: Pull 1,000 records of historical data from xDrip in a single batch at app start.
- **History View**: A scrollable list of every reading with timestamps, trend arrows, and extended metadata (device, noise, RSSI, system time).
- **Dynamic Y-Axis Scaling**: Charts automatically scale to fit the displayed data — minimum of 3.0 or floor of the lowest visible value, maximum of 12.0 or the highest visible value rounded up to the nearest even number.

### Smart Polling
- **Adaptive Fetch Interval**: Automatically schedules the next poll based on the age of the most recent reading, aligning fetches to expected 5-minute CGM update intervals.
- **Stale Data Warnings**: If data is older than 15 minutes, the menu bar updates to show `⏳ (Stale)` and the dashboard displays time since last reading.

### System Integration
- **Hide Dock Icon**: Run MacDrip as a menu-bar-only app — the dock icon can be hidden from Settings.
- **Launch at Login**: Generates a macOS LaunchAgent to start the app automatically on boot.
- **Open from Menu Bar**: Even with the dock icon hidden, the full dashboard window can be opened from the mini dashboard popover.
- **Zero-Cloud Dependency**: Queries the xDrip local web server directly. Your health data never leaves your local network.

## 📱 Prerequisites
- An Android phone running xDrip+.
- A Mac running macOS 13 (Ventura) or later.
- Both devices connected to the same local network/Wi-Fi or a Tailscale network.

## ⚙️ Phone Setup (xDrip+)
Before running the Mac app, you must expose the local API on your phone:

1. Open xDrip+ and go to **Settings > Inter-App Settings**.
2. Enable **xDrip Web-Server**.
3. Enable **Open Web Server** (allows other devices on your Wi-Fi to connect).
4. Go to **Settings > Cloud Upload > Nightscout Sync (REST-API)** and set an **API Secret**. You will need this password for the Mac app.

## 💻 Mac Setup & Installation
MacDrip compiles directly via the Swift command line — no Xcode project or formal Bundle ID required. An installation script handles compilation, app bundle creation, icon generation, code signing, and installation.
**Note the install script removes Gatekeeper protections from the app bundle to allow the unsigned app to run**.

Clone the repository:
```bash
git clone https://github.com/mwinterstorm/macdrip.git
cd macdrip
```

Run the installation script:
```bash
chmod +x install.sh
./install.sh
```

Once installed, open Spotlight (Cmd + Space) and search for **MacDrip** to launch.

## 🛠 Usage
1. Click the glucose reading in your macOS menu bar (e.g. `🩸 5.4 →`).
2. Click **Open App** to open the full dashboard, then navigate to **Settings**.
3. Enter your plain-text **API Secret** (the app hashes it securely with SHA-1 before sending).
4. Enter your phone's **IP Address** (local or Tailscale).
5. Set your **Predictive Low Alert Threshold** (e.g. 4.0 mmol/L).
6. Select your **Prediction Method** for Time-to-Low calculations.
7. Optionally toggle:
   - **Show 30-min Forecast on Dashboard** — displays the predicted value in the dashboard and mini popover.
   - **Hide Dock icon** — runs MacDrip as a menu-bar-only app.
   - **Launch automatically at login** — starts MacDrip on boot.

## ⚠️ Troubleshooting
- **"Net Error"**: Your Mac cannot reach the phone. Ensure the phone's screen is recently active, both devices are on the same Wi-Fi, and your router does not have "Client Isolation" enabled.
- **"Auth Error"**: The app reached the phone, but the API Secret is incorrect. Double-check your xDrip Nightscout settings.
- **"⏳ (Stale)"**: The Mac can reach the phone, but the phone hasn't received new data from the sensor in over 15 minutes. Check the phone's Bluetooth connection to the CGM.
- **"SGV Error"**: The API responded but returned no glucose values. Verify xDrip is actively receiving sensor data.

## 📁 Architecture
| File | Purpose |
|------|---------|
| `MacDripApp.swift` | App entry point, WindowGroup + MenuBarExtra scenes, AppDelegate |
| `ContentView.swift` | Dashboard, History, and Settings views |
| `MiniDashboardView.swift` | Compact menu bar popover |
| `GlucoseMonitor.swift` | Data fetching, prediction engine, polling scheduler |
| `Models.swift` | GlucoseReading model and PredictionMethod enum |
| `install.sh` | Build, bundle, sign, and install script |

## ⚖️ Disclaimer
This project is not a medical device. It is an open-source educational tool. Do not use this application to make medical or dosing decisions. Always refer to your primary CGM receiver or blood glucose meter.