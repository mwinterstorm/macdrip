# 🩸 MacDrip
A lightweight, native macOS menu bar application that displays real-time continuous glucose monitor (CGM) data directly from an Android phone running xDrip+.

Unlike standard setups that require bouncing medical data through a cloud-hosted Nightscout server, MacDrip connects to your phone directly over your local Wi-Fi network. This results in instant updates, zero hosting costs, and complete data privacy.

## ✨ Features
Native macOS UI: Built with modern SwiftUI for a clean, resource-light menu bar popover.

Zero-Cloud Dependency: Queries the xDrip local web server directly. Your health data never leaves your local router.

Subnet Auto-Discovery: Seamlessly handles dynamic IPs. If your phone's IP changes, MacDrip scans the local subnet and automatically reconnects to port 17580.

Secure Authentication: Implements SHA-1 hashing via Apple's CryptoKit to securely pass the API Secret to the xDrip server.

Launch at Login: Generates a silent macOS LaunchAgent to ensure the app starts automatically in the background when you boot your Mac.

## 📱 Prerequisites
An Android phone running xDrip+.

A Mac running macOS 13 or later.

Both devices connected to the same local network/Wi-Fi.

## ⚙️ Phone Setup (xDrip+)
Before running the Mac app, you must expose the local API on your phone:

Open xDrip+ and go to Settings > Inter-App Settings.

Enable xDrip Web-Server.

Enable Open Web Server (allows other devices on your Wi-Fi to connect).

Go to Settings > Cloud Upload > Nightscout Sync (REST-API) and set an API Secret. You will need this password for the Mac app.

## 💻 Mac Setup & Compilation
This app is designed to be compiled directly via the Swift Command Line, keeping the footprint tiny without needing a massive Xcode project file.

Clone the repository:

``` Bash
git clone https://github.com/mwinterstorm/macdrip.git
cd macdrip
```
Compile the app:

```Bash
swiftc MacDripApp.swift -parse-as-library -o macdrip-app
```

Run in the background:

```Bash
./macdrip-app &
```
## 🛠 Usage
Click the 🩸 icon in your macOS menu bar.

Click Settings.

Enter your plain-text API Secret (the app will hash it securely before sending).

If you know your phone's local IP, enter it manually. Otherwise, enable Auto-Discover to let the Mac find your phone automatically.

Click Save & Return to see your live glucose data.

## ⚠️ Troubleshooting
"Scan Failed" / "Net Error": Your Mac cannot reach the phone. Ensure the phone's screen is recently active, they are on the same Wi-Fi, and that your office/cafe router does not have "Client Isolation" turned on (which blocks devices from talking to each other).

"Auth Error": The app reached the phone, but the API Secret is incorrect. Double-check your xDrip Nightscout settings.

## ⚖️ Disclaimer
This project is not a medical device. It is an open-source educational tool. Do not use this application to make medical or dosing decisions. Always refer to your primary CGM receiver or blood glucose meter.