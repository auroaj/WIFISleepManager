# WiFi Sleep Manager

Menu bar app that automatically disables Wi-Fi when laptop lid closes and restores it when opened.

## Download
https://github.com/auroaj/WIFISleepManager/releases/latest/download/WiFiSleepManager.dmg
https://github.com/auroaj/WIFISleepManager/releases/download/v1.0.1/WiFiSleepManager-v1.0.1.dmg

## Features

- ✅ Wi-Fi disable/restore on lid close/open
- ✅ Optional Bluetooth management
- ✅ Optional other network services control
- ✅ Menu bar interface (system tray icon)
- ✅ **Auto-enabled on startup** - monitoring starts immediately
- ✅ Self-contained - no external dependencies
- ✅ Built-in sleep/wake monitoring via NSWorkspace
- ✅ Detailed logging with debug mode
- ✅ Clean state management

## Installation

1. Download `WiFiSleepManager.dmg`
2. Drag app to Applications
3. Launch - icon appears in menu bar
4. **Monitoring is enabled by default** - WiFi will auto-disable on sleep

## Usage

**Menu bar icon (🚫📶):**
- **Enable/Disable** - toggle WiFi sleep monitoring
- **Manage Bluetooth** - enable/disable Bluetooth management
- **Debug Logging** - toggle detailed logs
- Clear logs
- Show logs folder
- Quit

App runs in background with no dock icon. WiFi monitoring is **active by default** on app launch.

## Configuration Options

- **WiFi Management**: Always enabled when monitoring is on
- **Bluetooth Management**: Optional via menu (requires `blueutil`)
- **Other Network Services**: Optional via settings UI
- **Debug Logging**: Optional for troubleshooting

## Technical Details

- Uses NSWorkspace notifications + CGDisplay state monitoring
- Creates config in `~/.wifi-sleep-manager/`
- No external dependencies (sleepwatcher, scripts, etc.)
- Auto-starts monitoring on app launch
- Works on macOS 13.0+

## Building

### Prerequisites
- Xcode 15.0+
- macOS 13.0+ target

### Setup
```bash
# Create Xcode project
mkdir WiFiSleepManager && cd WiFiSleepManager
# Use provided Swift files and project structure
```

### Build
```bash
xcodebuild archive -project WiFiSleepManager.xcodeproj -scheme WiFiSleepManager -configuration Release -archivePath WiFiSleepManager.xcarchive

xcodebuild -exportArchive -archivePath WiFiSleepManager.xcarchive -exportPath . -exportOptionsPlist exportOptions.plist

hdiutil create -volname "WiFi Sleep Manager" -srcfolder WiFiSleepManager.app -format UDZO WiFiSleepManager.dmg
```

### Add App Icon
1. Create `Assets.xcassets/AppIcon.appiconset/`
2. Add PNG icons: 16x16, 32x32, 128x128, 256x256, 512x512, 1024x1024
   1. CLI command:
      ```
      for size in 16 32 128 256 512 1024; do
        sips -z $size $size wifi-sleep-icon.png --out icon_${size}x${size}.png
      done
      ```
3. Update `WiFiSleepManager/Assets.xcassets/AppIcon.appiconset/Contents.json`

## Project Structure

```
WiFiSleepManager/
├── WiFiSleepManager/
│   ├── WiFiSleepManagerApp.swift      # Menu bar app delegate + auto-start
│   ├── ContentView.swift              # Power management logic
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/        # App icons
│   ├── Info.plist
│   ├── WiFiSleepManager.entitlements
│   └── Preview Content/
├── WiFiSleepManager.xcodeproj/
└── README.md
```

## Files Created

- `~/.wifi-sleep-manager/app.log` - activity log
- `~/.wifi-sleep-manager/wifi_state` - temporary Wi-Fi state
- `~/.wifi-sleep-manager/bluetooth_state` - temporary Bluetooth state
- `~/.wifi-sleep-manager/disabled_services` - temporary network services list

Files auto-cleanup after wake cycle.

## Requirements

- macOS 13.0+
- No admin rights needed for basic Wi-Fi control
- Bluetooth management requires `blueutil` (optional, install via Homebrew: `brew install blueutil`)

## Behavior

1. **On first launch**: Monitoring starts automatically
2. **Lid close**: WiFi disabled (+ Bluetooth if enabled)
3. **Lid open**: WiFi restored to previous state
4. **Menu control**: Toggle monitoring on/off anytime
