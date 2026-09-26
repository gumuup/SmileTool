import Combine
import Foundation

struct DJIBluetoothDevice: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let batteryPercent: Int?
    var batteryReadAt: Date? = nil
    var batteryIsCached = false

    /// Retain a recent sample only for the same currently connected device.
    /// Missing reads do not renew the timestamp or keep stale values forever.
    static func retainingRecentBattery(_ rows: [Self], previous: [Self], now: Date) -> [Self] {
        rows.map { row in
            var result = row
            if row.batteryPercent != nil {
                result.batteryReadAt = now
                result.batteryIsCached = false
            } else if let old = previous.first(where: { normalizedAddress($0.id) == normalizedAddress(row.id) }),
                      let date = old.batteryReadAt, now.timeIntervalSince(date) >= 0,
                      now.timeIntervalSince(date) <= 600, old.batteryPercent != nil {
                result = Self(id: row.id, name: row.name, batteryPercent: old.batteryPercent,
                              batteryReadAt: date, batteryIsCached: true)
            }
            return result
        }
    }

    static func normalizedAddress(_ address: String) -> String {
        address.lowercased().filter { $0.isHexDigit }
    }

    static func parse(_ data: Data) throws -> [Self] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let sections = root?["SPBluetoothDataType"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var devices: [String: Self] = [:]
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, raw) in entry where name.hasPrefix("DJI Mic Mini 2") {
                    guard let properties = raw as? [String: Any],
                          let address = properties["device_address"] as? String else { continue }
                    let value = (properties["device_batteryLevelMain"] as? String)
                        .flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
                    devices[address] = Self(id: address, name: name,
                        batteryPercent: value.flatMap { (0...100).contains($0) ? $0 : nil })
                }
            }
        }
        return devices.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }
}

/// Read-only macOS Bluetooth inventory; never pairs devices or sends firmware commands.
@MainActor final class DJIBluetoothMonitor: ObservableObject {
    static let shared = DJIBluetoothMonitor()
    @Published private(set) var devices: [DJIBluetoothDevice] = []
    @Published private(set) var refreshing = false
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    private var timer: Timer?
    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    func refresh() {
        guard !refreshing else { return }; refreshing = true
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                    process.arguments = ["SPBluetoothDataType", "-json", "-timeout", "5"]
                    let pipe = Pipe(); process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
                    return try DJIBluetoothDevice.parse(data)
                }.value
                // IOBluetooth's synchronous pairedDevices can wait for permission
                // delivery on the main thread, deadlocking a newly signed app.
                // The bounded system profiler inventory already supplies connection
                // and battery observations without blocking the UI or pairing.
                devices = DJIBluetoothDevice.retainingRecentBattery(result, previous: devices, now: Date())
                updatedAt = Date(); error = nil
            } catch { self.error = "蓝牙状态读取失败，以下可能为上次结果。" }
            refreshing = false
        }
    }
}
