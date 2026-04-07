# 🩸 MacDrip
A lightweight, native macOS menu bar application that displays real-time continuous glucose monitor (CGM) data directly from an Android phone running xDrip+.

Unlike standard setups that require bouncing medical data through a cloud-hosted Nightscout server, MacDrip connects to your phone directly over your local Wi-Fi network. This results in instant updates, zero hosting costs, and complete data privacy.

## ✨ Features
- **Native macOS UI**: Built with modern SwiftUI for a clean, resource-light menu bar popover.
- **Smart Dynamic Polling**: Adapts its polling interval based on the age of the local data. 
- **Predictive Low Alerts**: Acts as an early warning system. MacDrip predicts where your glucose will be in 30 minutes using your choice of an Exponential Moving Average (EMA) or a classic linear rate of change. If it crosses your custom threshold, it throws a native macOS notification and prominently updates the menu bar icon to `⚠️ LOW PREDICTED`, keeping you safe without complex App Store bundles.
- **Stale Data Warnings & Timestamps**: Displays exactly how many minutes ago the data was received inside the popover. If the reading becomes older than 15 minutes, the menu bar icon updates to display a `⏳ (Stale)` warning.
- **Historical Graph**: Uses Swift Charts to display a dynamically scaled graphical representation of your glucose readings over the last 3 hours.
- **Zero-Cloud Dependency**: Queries the xDrip local web server directly. Your health data never leaves your local router.
- **Launch at Login**: Generates a silent macOS LaunchAgent to ensure the app starts automatically in the background when you boot your Mac.

## 📱 Prerequisites
- An Android phone running xDrip+.
- A Mac running macOS 13 or later.
- Both devices connected to the same local network/Wi-Fi or a Tailscale network.

## ⚙️ Phone Setup (xDrip+)
Before running the Mac app, you must expose the local API on your phone:

1. Open xDrip+ and go to **Settings > Inter-App Settings**.
2. Enable **xDrip Web-Server**.
3. Enable **Open Web Server** (allows other devices on your Wi-Fi to connect).
4. Go to **Settings > Cloud Upload > Nightscout Sync (REST-API)** and set an **API Secret**. You will need this password for the Mac app.

## 💻 Mac Setup & Installation
This app is designed to be compiled directly via the Swift Command Line, keeping the footprint tiny without needing a massive Xcode project file or a formal Bundle ID. An installation script is provided that will compile the binary, create a native macOS Application launcher, and move it to your Applications folder.

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

Once installed, you can open Spotlight (Cmd + Space) and search for 'Start MacDrip' to launch the app.

## 🛠 Usage
1. Click the 🩸 icon in your macOS menu bar.
2. Click **Settings**.
3. Enter your plain-text **API Secret** (the app will hash it securely before sending).
4. Enter your phone's **IP Address** (Local or Tailscale).
5. Set your **Predictive Low Alert Threshold** (e.g. 4.0 mmol/L).
6. Select your **Prediction Method** (this algorithm calculates your rate of change to trigger early warnings):
   - **EMA Smoothed** *(Default/Recommended)*: Uses an Exponential Moving Average to actively filter out sensor noise and calculate the true underlying direction. Excellent at preventing "false alarms" caused by a single bad reading.
   - **Linear (Classic)**: Looks strictly at the raw drop over the last 15 minutes. It is highly sensitive but more prone to false alarms if your blood sugar is naturally varying or leveling out.
7. Click **Save & Return** to see your live glucose data.

## ⚠️ Troubleshooting
- **"Scan Failed" / "Net Error"**: Your Mac cannot reach the phone. Ensure the phone's screen is recently active, they are on the same Wi-Fi, and that your office/cafe router does not have "Client Isolation" turned on.
- **"Auth Error"**: The app reached the phone, but the API Secret is incorrect. Double-check your xDrip Nightscout settings.
- **"⏳ (Stale)"**: The Mac can reach the phone's local server, but the phone itself hasn't received new data from the physical sensor in over 15 minutes. Check your phone's Bluetooth connection to the CGM.

## ⚖️ Disclaimer
This project is not a medical device. It is an open-source educational tool. Do not use this application to make medical or dosing decisions. Always refer to your primary CGM receiver or blood glucose meter.