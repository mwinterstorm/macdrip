#!/bin/bash

echo "🩸 Starting MacDrip Installation..."

# 1. Compile the Swift binary
echo "🔨 Compiling Swift application..."
swiftc *.swift -parse-as-library -o macdrip-app

# 2. Build standard Application Bundle
echo "📦 Generating the macOS Application Bundle..."
APP_NAME="MacDrip.app"
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

# 3. Dynamic Icon Compilation
if [ -f "icon.png" ]; then
    echo "🎨 Compiling App Icon natively from icon.png..."
    mkdir -p icon.iconset
    sips -z 16 16     icon.png --out icon.iconset/icon_16x16.png > /dev/null 2>&1
    sips -z 32 32     icon.png --out icon.iconset/icon_16x16@2x.png > /dev/null 2>&1
    sips -z 32 32     icon.png --out icon.iconset/icon_32x32.png > /dev/null 2>&1
    sips -z 64 64     icon.png --out icon.iconset/icon_32x32@2x.png > /dev/null 2>&1
    sips -z 128 128   icon.png --out icon.iconset/icon_128x128.png > /dev/null 2>&1
    sips -z 256 256   icon.png --out icon.iconset/icon_128x128@2x.png > /dev/null 2>&1
    sips -z 256 256   icon.png --out icon.iconset/icon_256x256.png > /dev/null 2>&1
    sips -z 512 512   icon.png --out icon.iconset/icon_256x256@2x.png > /dev/null 2>&1
    sips -z 512 512   icon.png --out icon.iconset/icon_512x512.png > /dev/null 2>&1
    sips -z 1024 1024 icon.png --out icon.iconset/icon_512x512@2x.png > /dev/null 2>&1
    iconutil -c icns icon.iconset -o "$APP_NAME/Contents/Resources/AppIcon.icns"
    rm -rf icon.iconset
fi

# Create minimal Info.plist
cat > "$APP_NAME/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>MacDrip</string>
    <key>CFBundleIdentifier</key>
    <string>com.macdrip.app</string>
    <key>CFBundleName</key>
    <string>MacDrip</string>
    <key>CFBundleVersion</key>
    <string>2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

cp macdrip-app "$APP_NAME/Contents/MacOS/MacDrip"

# Perform an ad-hoc local Code Signature to bypass modern Gatekeeper UI constraints
echo "🔐 Signing Apple bundle natively..."
codesign --force --deep --sign - "$APP_NAME" > /dev/null 2>&1

# Move to Applications
echo "🚀 Moving MacDrip to /Applications..."
rm -rf "/Applications/$APP_NAME"
mv "$APP_NAME" /Applications/

# Optionally clean up
rm macdrip-app

echo "✅ Installation Complete!"
echo "Open Spotlight (Cmd + Space) and search 'MacDrip' to launch."