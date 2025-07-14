import SwiftUI
import Foundation

class PowerManager: ObservableObject {
    @Published var isMonitoring = false

    var bluetoothEnabled = true
    var otherServicesEnabled = true
    var debugLogging = false

    private let configDir = NSHomeDirectory() + "/.wifi-sleep-manager"
    private var timer: Timer?
    private var wasAwake = true
    private var lastSleepActionTime: Date?
    private var lastWakeActionTime: Date?

    init() {
        try? createConfigDirectory()
        writeLog("App launched")
    }

    func startMonitoring() {
        isMonitoring = true
        writeLog("Monitoring started")

        // Clean up any existing state files for fresh start
        try? FileManager.default.removeItem(atPath: configDir + "/wifi_state")
        try? FileManager.default.removeItem(atPath: configDir + "/bluetooth_state")
        try? FileManager.default.removeItem(atPath: configDir + "/disabled_services")
        writeDebugLog("Cleared existing state files")

        registerForSleepNotifications()
    }

    func stopMonitoring() {
        isMonitoring = false
        unregisterForSleepNotifications()
        writeLog("Monitoring stopped")
    }

    private func registerForSleepNotifications() {
        writeDebugLog("Registering for sleep notifications")

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        writeDebugLog("Screen sleep notifications registered")

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        writeDebugLog("Screen wake notifications registered")

        startLidStateMonitoring()
    }

    private func startLidStateMonitoring() {
        writeDebugLog("Starting lid state monitoring")
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.checkLidState()
        }
    }

    private func checkLidState() {
        let currentlyAwake = CGDisplayIsActive(CGMainDisplayID()) != 0
        writeDebugLog("Lid state check: \(currentlyAwake ? "OPEN" : "CLOSED")")

        if wasAwake && !currentlyAwake {
            // Just went to sleep
            if lastSleepActionTime == nil || Date().timeIntervalSince(lastSleepActionTime!) > 5 {
                writeDebugLog("LID CLOSED DETECTED - triggering sleep actions")
                performSleepActions()
                lastSleepActionTime = Date()
            }
        } else if !wasAwake && currentlyAwake {
            // Just woke up
            if lastWakeActionTime == nil || Date().timeIntervalSince(lastWakeActionTime!) > 5 {
                writeDebugLog("LID OPENED DETECTED - triggering wake actions")
                performWakeActions()
                lastWakeActionTime = Date()
            }
        }

        wasAwake = currentlyAwake
    }

    private func unregisterForSleepNotifications() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func screenDidSleep() {
        writeDebugLog("=== SCREEN SLEEP EVENT RECEIVED ===")
        guard isMonitoring else {
            writeDebugLog("Monitoring disabled, ignoring screen sleep")
            return
        }

        // Save Wi-Fi state only on screen sleep (first trigger)
        if !FileManager.default.fileExists(atPath: configDir + "/wifi_state") {
            writeDebugLog("Saving Wi-Fi state on screen sleep...")
            saveWiFiState()
        }

        performSleepActions()
    }

    @objc private func screenDidWake() {
        writeDebugLog("=== SCREEN WAKE EVENT RECEIVED ===")
        guard isMonitoring else {
            writeDebugLog("Monitoring disabled, ignoring screen wake")
            return
        }
        performWakeActions()
    }

    private func checkPowerState() {
        writeDebugLog("Power state callback triggered")
    }

    private func performSleepActions() {
        writeDebugLog(">>> STARTING SLEEP ACTIONS <<<")
        writeDebugLog("Bluetooth enabled: \(bluetoothEnabled)")
        writeDebugLog("Other services enabled: \(otherServicesEnabled)")

        // Only save states if files don't exist (first sleep action)
        let wifiStateExists = FileManager.default.fileExists(atPath: configDir + "/wifi_state")
        let bluetoothStateExists = FileManager.default.fileExists(atPath: configDir + "/bluetooth_state")

        if bluetoothEnabled && !bluetoothStateExists {
            writeDebugLog("Saving Bluetooth state...")
            saveBluetoothState()
            writeDebugLog("Disabling Bluetooth...")
            disableBluetooth()
        } else {
            writeDebugLog("Bluetooth already managed or disabled")
        }

        if !wifiStateExists {
            writeDebugLog("Saving Wi-Fi state...")
            saveWiFiState()
        }
        writeDebugLog("Disabling Wi-Fi...")
        disableWiFi()

        if otherServicesEnabled {
            writeDebugLog("Disabling other network services...")
            disableOtherNetworkServices()
        } else {
            writeDebugLog("Other services management disabled")
        }

        writeDebugLog(">>> SLEEP ACTIONS COMPLETED <<<")
    }

    private func performWakeActions() {
        writeDebugLog(">>> STARTING WAKE ACTIONS <<<")

        if bluetoothEnabled {
            writeDebugLog("Restoring Bluetooth state...")
            restoreBluetoothState()
        } else {
            writeDebugLog("Bluetooth management disabled")
        }

        writeDebugLog("Restoring Wi-Fi state...")
        restoreWiFiState()

        if otherServicesEnabled {
            writeDebugLog("Restoring other network services...")
            restoreOtherNetworkServices()
        } else {
            writeDebugLog("Other services management disabled")
        }

        // Clean up state files after restoration
        try? FileManager.default.removeItem(atPath: configDir + "/wifi_state")
        try? FileManager.default.removeItem(atPath: configDir + "/bluetooth_state")
        try? FileManager.default.removeItem(atPath: configDir + "/disabled_services")
        writeDebugLog("State files cleaned up")

        writeDebugLog(">>> WAKE ACTIONS COMPLETED <<<")
    }

    private func saveBluetoothState() {
        guard commandExists("blueutil") else { return }

        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["blueutil", "-p"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            try? output.write(toFile: configDir + "/bluetooth_state", atomically: true, encoding: .utf8)
        }
    }

    private func disableBluetooth() {
        guard commandExists("blueutil") else { return }

        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["blueutil", "-p", "0"]
        task.launch()
    }

    private func restoreBluetoothState() {
        guard let state = try? String(contentsOfFile: configDir + "/bluetooth_state").trimmingCharacters(in: .whitespacesAndNewlines),
              state == "1",
              commandExists("blueutil") else { return }

        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["blueutil", "-p", "1"]
        task.launch()
    }

    private func saveWiFiState() {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-getairportpower", "en0"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let state = output.contains("On") ? "1" : "0"
        writeDebugLog("Current Wi-Fi state: \(output.trimmingCharacters(in: .whitespacesAndNewlines)) -> saving '\(state)'")
        try? state.write(toFile: configDir + "/wifi_state", atomically: true, encoding: .utf8)
    }

    private func disableWiFi() {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-setairportpower", "en0", "off"]
        task.launch()
        writeDebugLog("Wi-Fi disabled")
    }

    private func restoreWiFiState() {
        guard let state = try? String(contentsOfFile: configDir + "/wifi_state").trimmingCharacters(in: .whitespacesAndNewlines) else {
            writeDebugLog("No wifi_state file found")
            return
        }

        writeDebugLog("Restoring Wi-Fi state from file: '\(state)'")

        if state == "1" {
            let task = Process()
            task.launchPath = "/usr/sbin/networksetup"
            task.arguments = ["-setairportpower", "en0", "on"]
            task.launch()
            writeDebugLog("Wi-Fi enabled")
        } else {
            writeDebugLog("Wi-Fi was already off, not restoring")
        }
    }

    private func disableOtherNetworkServices() {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-listallnetworkservices"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }

        let services = output.components(separatedBy: .newlines)
            .dropFirst()
            .filter { !$0.isEmpty && !$0.contains("Wi-Fi") && !$0.hasPrefix("*") }

        var disabledServices: [String] = []

        for service in services {
            let disableTask = Process()
            disableTask.launchPath = "/usr/sbin/networksetup"
            disableTask.arguments = ["-setnetworkserviceenabled", service, "off"]
            disableTask.launch()
            disableTask.waitUntilExit()

            if disableTask.terminationStatus == 0 {
                disabledServices.append(service)
            }
        }

        let disabledList = disabledServices.joined(separator: "\n")
        try? disabledList.write(toFile: configDir + "/disabled_services", atomically: true, encoding: .utf8)
    }

    private func restoreOtherNetworkServices() {
        guard let content = try? String(contentsOfFile: configDir + "/disabled_services") else { return }

        let services = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for service in services {
            let enableTask = Process()
            enableTask.launchPath = "/usr/sbin/networksetup"
            enableTask.arguments = ["-setnetworkserviceenabled", service, "on"]
            enableTask.launch()
        }
    }

    private func commandExists(_ command: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [command]
        task.standardOutput = Pipe()
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}

// MARK: - Utility Functions
extension PowerManager {
    private func createConfigDirectory() throws {
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    }

    private func writeLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let logEntry = "\(timestamp): \(message)\n"
        let logPath = configDir + "/app.log"

        if let data = logEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    private func writeDebugLog(_ message: String) {
        guard debugLogging else { return }
        writeLog("DEBUG: \(message)")
    }

    func clearLogFile() {
        let logPath = configDir + "/app.log"
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
    }

    func getConfigFiles() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: configDir) else {
            return []
        }
        return files.map { configDir + "/" + $0 }
    }

    func removeAllFiles() {
        stopMonitoring()
        try? FileManager.default.removeItem(atPath: configDir)
        isMonitoring = false
    }
}

struct ContentView: View {
    @StateObject private var powerManager = PowerManager()
    @State private var bluetoothEnabled = true
    @State private var otherServicesEnabled = true
    @State private var selectedTab = 0
    @State private var showDeleteAlert = false
    @State private var showResult = false
    @State private var resultMessage = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "wifi.slash")
                        .font(.title)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading) {
                        Text("WiFi Sleep Manager")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    Spacer()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 15) {
                    Toggle("Disable Wi-Fi on sleep", isOn: $powerManager.isMonitoring)
                        .onChange(of: powerManager.isMonitoring) { newValue in
                            if newValue {
                                powerManager.startMonitoring()
                            } else {
                                powerManager.stopMonitoring()
                            }
                        }

                    Toggle("Manage Bluetooth", isOn: $bluetoothEnabled)
                        .disabled(!powerManager.isMonitoring)
                        .onChange(of: bluetoothEnabled) { newValue in
                            powerManager.bluetoothEnabled = newValue
                        }

                    Toggle("Disable other network services", isOn: $otherServicesEnabled)
                        .disabled(!powerManager.isMonitoring)
                        .onChange(of: otherServicesEnabled) { newValue in
                            powerManager.otherServicesEnabled = newValue
                        }
                }

                Divider()

                HStack {
                    Text("Status:")
                        .fontWeight(.semibold)

                    Text(powerManager.isMonitoring ? "Active" : "Inactive")
                        .foregroundColor(powerManager.isMonitoring ? .green : .red)

                    Spacer()
                }
            }
            .padding()
            .tabItem {
                Image(systemName: "wifi")
                Text("Main")
            }
            .tag(0)

            VStack(spacing: 20) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                Divider()

                VStack(spacing: 15) {
                    Button("Clear Log File") {
                        powerManager.clearLogFile()
                        resultMessage = "Log file cleared"
                        showResult = true
                    }

                    Button("Remove All Files") {
                        showDeleteAlert = true
                    }
                    .foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
            .tabItem {
                Image(systemName: "gear")
                Text("Settings")
            }
            .tag(1)
        }
        .frame(width: 350, height: 250)
        .onAppear {
            powerManager.bluetoothEnabled = bluetoothEnabled
            powerManager.otherServicesEnabled = otherServicesEnabled
        }
        .alert("Remove All Files", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                let files = powerManager.getConfigFiles()
                powerManager.removeAllFiles()
                resultMessage = files.isEmpty ? "No files to remove" : "Removed:\n" + files.joined(separator: "\n")
                showResult = true
            }
        } message: {
            Text("This will remove all configuration files and stop monitoring.")
        }
        .alert("Result", isPresented: $showResult) {
            Button("OK") { }
        } message: {
            Text(resultMessage)
        }
    }
}

#Preview {
    ContentView()
}
