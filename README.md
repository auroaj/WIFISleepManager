# WiFi Sleep Manager - macOS App

## Project Structure

```
WiFiSleepManager/
├── WiFiSleepManager/
│   ├── WiFiSleepManagerApp.swift
│   ├── ContentView.swift
│   ├── Info.plist
│   └── WiFiSleepManager.entitlements
├── WiFiSleepManager.xcodeproj
└── README.md
```

## Xcode Project Setup

1. **Create new project:**
   - File → New → Project
   - macOS → App
   - Product Name: `WiFiSleepManager`
   - Interface: SwiftUI
   - Language: Swift

2. **Add files:**
   - Replace `ContentView.swift` with provided code
   - Update `Info.plist`
   - Add `WiFiSleepManager.entitlements`

3. **Configure project:**
   - Target → Signing & Capabilities → Disable App Sandbox
   - Add Capability → Hardened Runtime
   - Deployment Target: macOS 13.0

## Dependencies

No external dependencies required! Uses built-in macOS IOKit APIs for sleep/wake monitoring.

## Features

- ✅ Automatic Wi-Fi disable when lid closes
- ✅ Wi-Fi restore on wake
- ✅ Optional Bluetooth management
- ✅ Disable other network services
- ✅ Simple configuration UI
- ✅ Automatic script installation/removal
- ✅ Organized configuration directory

## Build for Distribution

1. **Archive build:**
   ```bash
   xcodebuild -project WiFiSleepManager.xcodeproj -scheme WiFiSleepManager -configuration Release -archivePath WiFiSleepManager.xcarchive archive
   ```

2. **Export .app:**
   ```bash
   xcodebuild -exportArchive -archivePath WiFiSleepManager.xcarchive -exportPath . -exportOptionsPlist exportOptions.plist
   ```

3. **Create DMG:**
   ```bash
   hdiutil create -volname "WiFi Sleep Manager" -srcfolder WiFiSleepManager.app -ov -format UDZO WiFiSleepManager.dmg
   ```

## Usage

1. Launch application
2. Enable "Disable Wi-Fi on sleep" toggle
3. Configure additional options
4. App creates necessary scripts and launch agent

## Requirements

- macOS 13.0+
- Administrator access (for networksetup commands)
- Homebrew for sleepwatcher installation

## File Organization

App creates organized configuration in `~/.wifi-sleep-manager/`:
- `sleep.sh` - script executed on sleep
- `wakeup.sh` - script executed on wake
- `config.json` - settings configuration
- `wifi_state`, `bluetooth_state` - state files
- `disabled_services` - list of disabled services
- `sleepwatcher.log` - log file
- `~/Library/LaunchAgents/com.wifisleepmanager.plist` - launch agent

All files can be removed via app interface.
