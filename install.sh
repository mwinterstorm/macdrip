#!/bin/bash

echo "🩸 Starting MacDrip Installation..."

# 1. Get the exact absolute path of wherever the user downloaded the folder
INSTALL_DIR=$(pwd)

# 2. Compile the Swift binary
echo "🔨 Compiling Swift application..."
swiftc MacDripApp.swift -parse-as-library -o macdrip-app

# 3. Create the AppleScript payload 
echo "📦 Generating the background launcher..."
APPLESCRIPT_PAYLOAD="do shell script \"nohup ${INSTALL_DIR}/macdrip-app > /dev/null 2>&1 &\""

# 4. Use osacompile to build a native macOS .app from the script
osacompile -e "$APPLESCRIPT_PAYLOAD" -o "Start MacDrip.app"

# 5. Move the launcher to Applications folder
echo "🚀 Moving launcher to /Applications..."
mv "Start MacDrip.app" /Applications/

echo "✅ Installation Complete!"
echo "Open Spotlight (Cmd + Space) and search 'Start MacDrip' to launch."