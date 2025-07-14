import SwiftUI
import Foundation

class PowerManager: ObservableObject {
    @Published var isMonitoring = false

    var bluetoothEnabled = true
    var otherServicesEnabled = true

    private let configDir = NSHomeDirectory() + "/.wifi-sleep-manager"
    private var sleepwatcherProcess: Process?

    init() {
        try? createConfigDirectory()
        writeLog("App launched")
    }

    func startMonitoring() {
        isMonitoring = true
        writeLog("Monitoring started")
        createScripts()
        installAndStartSleepwatcher()
    }

    func stopMonitoring() {
        isMonitoring = false
        sleepwatcherProcess?.terminate()
        writeLog("Monitoring stopped")
    }

    private func createScripts() {
        let sleepScript = """
#!/bin/zsh

# Save and disable Bluetooth
if command -v blueutil >/dev/null 2>&1; then
    echo $(blueutil -p) > "\(configDir)/bluetooth_state"
    bluestatus=$(head -n 1 "\(configDir)/bluetooth_state")
    if [[ "$bluestatus" != "0" ]]; then
        blueutil -p 0
    fi
fi

# Save and disable Wi-Fi
if [[ $(networksetup -getairportpower en0) =~ "On" ]]; then
    echo 1 > "\(configDir)/wifi_state"
    networksetup -setairportpower en0 off
else
    echo 0 > "\(configDir)/wifi_state"
fi

# Disable other network services
services=$(networksetup -listallnetworkservices | sed '1d' | grep -v "Wi-Fi")
echo "" > "\(configDir)/disabled_services"
while IFS= read -r service; do
    if [[ $service != \\** ]]; then
        echo "$service" >> "\(configDir)/disabled_services"
        networksetup -setnetworkserviceenabled "$service" off
    fi
done <<< "$services"
"""

        let wakeScript = """
#!/bin/zsh

# Restore Bluetooth
if [[ -f "\(configDir)/bluetooth_state" ]]; then
    bluestatus=$(head -n 1 "\(configDir)/bluetooth_state")
    if [[ "$bluestatus" != "0" ]] && command -v blueutil >/dev/null 2>&1; then
        blueutil -p 1
    fi
fi

# Restore Wi-Fi
if [[ -f "\(configDir)/wifi_state" ]]; then
    wifistatus=$(head -n 1 "\(configDir)/wifi_state")
    if [[ "$wifistatus" != "0" ]]; then
        networksetup -setairportpower en0 on
    fi
fi

# Restore other network services
if [[ -f "\(configDir)/disabled_services" ]]; then
    while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            networksetup -setnetworkserviceenabled "$service" on
        fi
    done < "\(configDir)/disabled_services"
fi
"""

        let sleepwatcherBinary = sleepwatcherBinaryData()

        try? sleepScript.write(toFile: configDir + "/sleep.sh", atomically: true, encoding: .utf8)
        try? wakeScript.write(toFile: configDir + "/wakeup.sh", atomically: true, encoding: .utf8)
        try? sleepwatcherBinary.write(to: URL(fileURLWithPath: configDir + "/sleepwatcher"))

        makeExecutable(configDir + "/sleep.sh")
        makeExecutable(configDir + "/wakeup.sh")
        makeExecutable(configDir + "/sleepwatcher")
    }

    private func makeExecutable(_ path: String) {
        let task = Process()
        task.launchPath = "/bin/chmod"
        task.arguments = ["+x", path]
        task.launch()
        task.waitUntilExit()
    }

    private func installAndStartSleepwatcher() {
        sleepwatcherProcess = Process()
        sleepwatcherProcess?.launchPath = configDir + "/sleepwatcher"
        sleepwatcherProcess?.arguments = ["-V", "-s", configDir + "/sleep.sh", "-w", configDir + "/wakeup.sh"]

        do {
            try sleepwatcherProcess?.run()
            writeLog("Sleepwatcher started")
        } catch {
            writeLog("Failed to start sleepwatcher: \(error)")
        }
    }

    private func sleepwatcherBinaryData() -> Data {
        // Embedded sleepwatcher binary for arm64 macOS
        // This is a placeholder - you'd need to include the actual binary
        // For now, try to copy from system if available
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/usr/local/bin/sleepwatcher")) {
            return data
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: "/opt/homebrew/bin/sleepwatcher")) {
            return data
        }
        return Data()
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
        let logPath = configDir + "/app.log"
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath),
              let fileSize = attributes[.size] as? Int64 else { return }

        if fileSize > 1_048_576 {
            try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        }
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
