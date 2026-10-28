import Foundation

/// Works out whether an address belongs to a keyboard or a pointing device.
///
/// CoreBluetooth will not say (`retrievePairingInfoForPeripheral:` comes back empty), so
/// `system_profiler` is parsed instead. That is slow (~1-2 s), hence the background queue
/// and the cache. An address that cannot be classified stays `.other` and is not boosted;
/// only a device recognised as a keyboard is.
final class DeviceInventory {
    private var kinds: [String: DeviceKind] = [:]
    private var lastRefresh: Date = .distantPast
    /// Addresses that were unclassified when the last parse started. A parse is retried
    /// immediately only when a *new* address shows up, not on every tick.
    private var attempted: Set<String> = []
    private var refreshing = false
    private let queue = DispatchQueue(label: "keyawake.inventory")
    private let minimumInterval: TimeInterval = 60

    func kind(for address: String) -> DeviceKind {
        queue.sync { kinds[address.uppercased()] ?? .other }
    }

    /// Re-runs the parse when there are unclassified addresses and the interval has passed.
    func refreshIfNeeded(addresses: [String]) {
        let unknown = queue.sync {
            Set(addresses.map { $0.uppercased() }.filter { kinds[$0] == nil })
        }
        guard !unknown.isEmpty || Date().timeIntervalSince(lastRefresh) > 600 else { return }
        // A keyboard that reconnects under a new address must not wait out the regular
        // interval: the engine only boosts addresses it knows are keyboards.
        let hasNewDevice = !unknown.isSubset(of: attempted)
        guard hasNewDevice || Date().timeIntervalSince(lastRefresh) > minimumInterval else { return }
        let started = queue.sync { () -> Bool in
            guard !refreshing else { return false }
            refreshing = true
            return true
        }
        guard started else { return }
        lastRefresh = Date()
        attempted = unknown
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = Self.parseSystemProfiler()
            self?.queue.sync {
                for (k, v) in parsed { self?.kinds[k] = v }
                self?.refreshing = false
            }
        }
    }

    private static func parseSystemProfiler() -> [String: DeviceKind] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [:] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        // Within each device block, "Address:" comes before "Minor Type:".
        var result: [String: DeviceKind] = [:]
        var current: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Address:") {
                current = line.dropFirst("Address:".count)
                    .trimmingCharacters(in: .whitespaces).uppercased()
            } else if line.hasPrefix("Minor Type:"), let address = current {
                let value = line.dropFirst("Minor Type:".count).trimmingCharacters(in: .whitespaces).lowercased()
                if value.contains("keyboard") {
                    result[address] = .keyboard
                } else if value.contains("mouse") || value.contains("trackpad") || value.contains("pointing") {
                    result[address] = .pointing
                } else {
                    result[address] = .other
                }
                current = nil
            }
        }
        return result
    }
}
