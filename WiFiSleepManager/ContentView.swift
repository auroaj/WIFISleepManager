import SwiftUI
import Foundation

class PowerManager: ObservableObject {
    @Published var isMonitoring = false

    var bluetoothEnabled = true
    var otherServicesEnabled = true

    private let configDir = NSHomeDirectory() + "/.wifi-sleep-manager"

    init() {
        setupNotifications()
    }

    private func setupNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep() {
        guard isMonitoring else { return }

        checkAndClearLogIfNeeded()

        if bluetoothEnabled {
            saveBluetoothState()
            disableBluetooth()
        }

        saveWiFiState()
        disableWiFi()

        if otherServicesEnabled {
            disableOtherNetworkServices()
        }
    }

    @objc private func systemDidWake() {
        guard isMonitoring else { return }

        if bluetoothEnabled {
            restoreBluetoothState()
        }

        restoreWiFiState()

        if otherServicesEnabled {
            restoreOtherNetworkServices()
        }
    }

    func startMonitoring() {
        isMonitoring = true
        try? createConfigDirectory()
    }

    func stopMonitoring() {
        isMonitoring = false
    }
}

// MARK: - Network Management
extension PowerManager {
    private func createConfigDirectory() throws {
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    }

    private func checkAndClearLogIfNeeded() {
        let logPath = configDir + "/sleepwatcher.log"
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath),
              let fileSize = attributes[.size] as? Int64 else { return }

        // Clear if larger than 1MB
        if fileSize > 1_048_576 {
            try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }

    func clearLogFile() {
        let logPath = configDir + "/sleepwatcher.log"
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
    }

    func removeAllFiles() {
        stopMonitoring()
        try? FileManager.default.removeItem(atPath: configDir)
        isMonitoring = false
    }

    private func saveBluetoothState() {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["blueutil"]
        task.launch()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else { return }

        let bluetoothTask = Process()
        bluetoothTask.launchPath = "/usr/local/bin/blueutil"
        bluetoothTask.arguments = ["-p"]

        let pipe = Pipe()
        bluetoothTask.standardOutput = pipe
        bluetoothTask.launch()
        bluetoothTask.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            try? output.write(toFile: configDir + "/bluetooth_state", atomically: true, encoding: .utf8)
        }
    }

    private func disableBluetooth() {
        let task = Process()
        task.launchPath = "/usr/local/bin/blueutil"
        task.arguments = ["-p", "0"]
        task.launch()
    }

    private func restoreBluetoothState() {
        guard let state = try? String(contentsOfFile: configDir + "/bluetooth_state").trimmingCharacters(in: .whitespacesAndNewlines),
              state == "1" else { return }

        let task = Process()
        task.launchPath = "/usr/local/bin/blueutil"
        task.arguments = ["-p", "1"]
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
        if let output = String(data: data, encoding: .utf8), output.contains("On") {
            try? "1".write(toFile: configDir + "/wifi_state", atomically: true, encoding: .utf8)
        } else {
            try? "0".write(toFile: configDir + "/wifi_state", atomically: true, encoding: .utf8)
        }
    }

    private func disableWiFi() {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-setairportpower", "en0", "off"]
        task.launch()
    }

    private func restoreWiFiState() {
        guard let state = try? String(contentsOfFile: configDir + "/wifi_state").trimmingCharacters(in: .whitespacesAndNewlines),
              state == "1" else { return }

        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-setairportpower", "en0", "on"]
        task.launch()
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
}

struct ContentView: View {
    @StateObject private var powerManager = PowerManager()
    @State private var bluetoothEnabled = true
    @State private var otherServicesEnabled = true
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Main tab
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

            // Settings tab
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                Divider()

                VStack(spacing: 15) {
                    Button("Clear Log File") {
                        powerManager.clearLogFile()
                    }

                    Button("Remove All Files") {
                        powerManager.removeAllFiles()
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
    }
}

#Preview {
    ContentView()
}
