import SwiftUI
import Foundation

class PowerManager: ObservableObject {
    @Published var isMonitoring = false

    var bluetoothEnabled = true
    var otherServicesEnabled = true

    private let configDir = NSHomeDirectory() + "/.wifi-sleep-manager"

    init() {
        try? createConfigDirectory()
        writeLog("App launched")
    }

    func startMonitoring() {
        isMonitoring = true
        writeLog("Monitoring started")
        createSleepScripts()
        startSleepwatcher()
    }

    func stopMonitoring() {
        isMonitoring = false
        stopSleepwatcher()
        writeLog("Monitoring stopped")
    }

    private func createSleepScripts() {
        let sleepScript = """
#!/bin/zsh
\(bluetoothEnabled ? """
echo $(blueutil -p) > "\(configDir)/bluetooth_state"
if [[ "$(head -n 1 "\(configDir)/bluetooth_state")" != "0" ]]; then
    blueutil -p 0
fi
""" : "")

if [[ $(networksetup -getairportpower en0) =~ "On" ]]; then
    echo 1 > "\(configDir)/wifi_state"
    networksetup -setairportpower en0 off
else
    echo 0 > "\(configDir)/wifi_state"
fi
"""

        let wakeScript = """
#!/bin/zsh
\(bluetoothEnabled ? """
if [[ -f "\(configDir)/bluetooth_state" && "$(head -n 1 "\(configDir)/bluetooth_state")" != "0" ]]; then
    blueutil -p 1
fi
""" : "")

if [[ -f "\(configDir)/wifi_state" && "$(head -n 1 "\(configDir)/wifi_state")" != "0" ]]; then
    networksetup -setairportpower en0 on
fi
"""

        try? sleepScript.write(toFile: configDir + "/sleep.sh", atomically: true, encoding: .utf8)
        try? wakeScript.write(toFile: configDir + "/wakeup.sh", atomically: true, encoding: .utf8)

        makeExecutable(configDir + "/sleep.sh")
        makeExecutable(configDir + "/wakeup.sh")
    }

    private func makeExecutable(_ path: String) {
        let task = Process()
        task.launchPath = "/bin/chmod"
        task.arguments = ["+x", path]
        task.launch()
        task.waitUntilExit()
    }

    private func startSleepwatcher() {
        let task = Process()
        task.launchPath = "/usr/local/bin/sleepwatcher"
        task.arguments = ["-V", "-s", configDir + "/sleep.sh", "-w", configDir + "/wakeup.sh"]
        task.launch()

        writeLog("Sleepwatcher started")
    }

    private func stopSleepwatcher() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["sleepwatcher"]
        task.launch()
        task.waitUntilExit()
    }
}

// MARK: - Network Management
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
    @State private var showDeleteAlert = false
    @State private var showResult = false
    @State private var resultMessage = ""

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

            // Settings tab
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
