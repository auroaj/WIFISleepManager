import SwiftUI

@main
struct WiFiSleepManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var powerManager = PowerManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "WiFi Sleep Manager")

        powerManager.startMonitoring()

        setupMenu()
    }

    func setupMenu() {
        let menu = NSMenu()

        let enableItem = NSMenuItem(title: powerManager.isMonitoring ? "Disable" : "Enable", action: #selector(toggleMonitoring), keyEquivalent: "")
        enableItem.target = self
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        let bluetoothItem = NSMenuItem(title: "Manage Bluetooth", action: #selector(toggleBluetooth), keyEquivalent: "")
        bluetoothItem.target = self
        bluetoothItem.state = powerManager.bluetoothEnabled ? .on : .off
        menu.addItem(bluetoothItem)

        let debugItem = NSMenuItem(title: "Debug Logging", action: #selector(toggleDebugLogging), keyEquivalent: "")
        debugItem.target = self
        debugItem.state = powerManager.debugLogging ? .on : .off
        menu.addItem(debugItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear Logs", action: #selector(clearLogs), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Logs", action: #selector(showLogs), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func toggleMonitoring() {
        if powerManager.isMonitoring {
            powerManager.stopMonitoring()
        } else {
            powerManager.startMonitoring()
        }
        setupMenu() // Refresh menu
    }

    @objc func toggleBluetooth() {
        powerManager.bluetoothEnabled.toggle()
        setupMenu() // Refresh menu
    }

    @objc func toggleDebugLogging() {
        powerManager.debugLogging.toggle()
        setupMenu() // Refresh menu
    }

    @objc func clearLogs() {
        powerManager.clearLogFile()
    }

    @objc func showLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.wifi-sleep-manager"))
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
