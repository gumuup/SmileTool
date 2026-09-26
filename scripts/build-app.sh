#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/SmileTool"
APP="$ROOT/dist/SmileTool.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SmileTool"
cp Sources/SmileTool/Resources/*.png "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
mkdir -p "$APP/Contents/Resources/ThirdParty"
cp -R ThirdParty/. "$APP/Contents/Resources/ThirdParty/"
if [[ -f Sources/SmileTool/Resources/AppIcon.icns ]]; then
    cp Sources/SmileTool/Resources/AppIcon.icns "$APP/Contents/Resources/"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SmileTool</string>
<key>CFBundleIdentifier</key><string>com.gumu.smiletool</string>
<key>CFBundleName</key><string>SmileTool</string>
<key>CFBundleDisplayName</key><string>SmileTool</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>SmileTool 使用你选择的音频设备进行输入测试与语音混音。</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>SmileTool 通过蓝牙连接遥控器语音服务并读取设备状态。</string>
<key>NSBluetoothPeripheralUsageDescription</key><string>SmileTool 通过蓝牙连接遥控器。</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
