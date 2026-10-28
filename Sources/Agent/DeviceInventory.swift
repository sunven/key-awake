import Foundation

/// Works out whether an address belongs to a keyboard or a pointing device.
///
/// CoreBluetooth will not say (`retrievePairingInfoForPeripheral:` comes back empty), so
/// `system_profiler` is parsed instead. That is slow (~1-2 s), hence the background queue
/// and the cache. An address that cannot be classified stays `.other` and is not boosted;
/// only a device recognised as a keyboard is.
final class DeviceInventory {
    private var kinds: [String: DeviceKind] = [:]
    private var policy = RefreshPolicy()
    private let queue = DispatchQueue(label: "keyawake.inventory")

    func kind(for address: String) -> DeviceKind {
        queue.sync { kinds[address.uppercased()] ?? .other }
    }

    /// Re-runs the parse when there are unclassified addresses and the interval has passed.
    func refreshIfNeeded(addresses: [String]) {
        let unknown = queue.sync {
            Set(addresses.map { $0.uppercased() }.filter { kinds[$0] == nil })
        }
        let started = queue.sync { policy.begin(unknown: unknown, now: Date()) }
        guard started else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = Self.parseSystemProfiler()
            self?.queue.sync {
                for (k, v) in parsed { self?.kinds[k] = v }
                self?.policy.finish()
            }
        }
    }

    private static func parseSystemProfiler() -> [String: DeviceKind] {
        guard let data = ProcessRunner.output("/usr/sbin/system_profiler", ["SPBluetoothDataType"]),
              let text = String(data: data, encoding: .utf8) else { return [:] }
        return SystemProfiler.kinds(from: text)
    }
}
