import Foundation

/// A device visible right now, without the CoreBluetooth handle.
struct ObservedDevice: Equatable {
    let address: String
    let name: String
    /// False when `name` is the placeholder built from the address.
    let hasRealName: Bool
}

/// Decides one tick: which devices are wanted, boosted or released, which identities are
/// learned, which rows the interface sees, and which samples are due.
///
/// Pure by design: the controller supplies the snapshot and applies the actions. The
/// post-action `boosted` flag is computed here so a tick is fully determined by its input.
enum BoostPolicy {
    struct State: Equatable {
        /// When the link last became continuously boosted. A loss figure measured across a
        /// reconnect counts the silence as lost packets and reports a fault that is not there.
        var boostedSince: Date?
        var lastRSSISample: Date = .distantPast
        var lastHistoryWrite: Date = .distantPast
        /// Uppercased address → last known name, so absent devices are not shown as "unknown".
        var knownNames: [String: String] = [:]
    }

    struct Input {
        var settings: Settings
        var live: [ObservedDevice]
        /// Uppercased hardware address → kind, covering live devices and every alias.
        var kinds: [String: DeviceKind]
        /// Uppercased addresses whose peripheral is physically connected at tick start.
        var connected: Set<String>
        var idleSeconds: Double
        var now: Date
    }

    enum Action: Equatable {
        case boost(address: String)
        case release(address: String)
    }

    struct Sampling: Equatable {
        var readRSSI: Bool
        var recordHistory: Bool
        /// False while the link is too freshly established for a loss figure to mean anything.
        var measureLoss: Bool
    }

    struct Decision: Equatable {
        var actions: [Action]
        var learned: [ObservedDevice]
        var devices: [DeviceStatus]
        var sampling: Sampling
        /// Whether any device is boosted after the actions are applied.
        var boosted: Bool
        var state: State
    }

    static func decide(_ state: State, _ input: Input) -> Decision {
        var state = state
        var settings = input.settings
        let live = input.live

        for device in live {
            state.knownNames[device.address.uppercased()] = device.name
        }

        func kind(of address: String) -> DeviceKind {
            input.kinds[address.uppercased()] ?? .other
        }

        // An address match is definitive. A name match is a fallback for the one case it
        // exists to cover — the device came back under a new address — so it only applies
        // when none of that record's known addresses is currently live. Without that
        // condition a second keyboard reporting the same name would be adopted silently.
        func isWanted(_ device: ObservedDevice) -> Bool {
            guard settings.enabled else { return false }
            if settings.boosts(address: device.address) { return true }
            guard device.hasRealName, let record = settings.record(forName: device.name) else { return false }
            return !record.addresses.contains { alias in
                live.contains { $0.address.caseInsensitiveCompare(alias) == .orderedSame }
            }
        }

        var actions: [Action] = []
        var learned: [ObservedDevice] = []
        var devices: [DeviceStatus] = []
        var anyBoosted = false
        let idleLimit = settings.idleReleaseSeconds

        for device in live {
            let kind = kind(of: device.address)
            // Keyboards only. On macOS 27.0.1, asking for low latency on a pointing device
            // as well makes bluetoothd's HID layer enter its multi-HID power mode and
            // re-apply the keyboard's idle profile (latency 44) right after the request.
            let wanted = kind == .keyboard && isWanted(device)
            // The engine holds the link immediately on boost, so a physically connected
            // device is boosted by the end of the tick; a new connect lands on the next one.
            let wasConnected = input.connected.contains(device.address.uppercased())
            var boosted = false

            if wanted {
                // Recognising a device by one identifier teaches us the other, so the next
                // power cycle cannot drop it out of the set.
                if settings.learn(address: device.address, name: device.name,
                                  nameIsReal: device.hasRealName) {
                    learned.append(device)
                }
                let keepAwake = idleLimit == 0 || input.idleSeconds < Double(idleLimit)
                if keepAwake {
                    actions.append(.boost(address: device.address))
                    boosted = wasConnected
                } else {
                    actions.append(.release(address: device.address))
                }
            } else {
                actions.append(.release(address: device.address))
            }

            anyBoosted = anyBoosted || boosted
            devices.append(DeviceStatus(address: device.address, name: device.name,
                                        kind: kind, present: true, wanted: wanted, boosted: boosted))
        }

        // Configured but not visible: one row per record, so a device with several known
        // addresses cannot render twice.
        for record in settings.boosted {
            let liveHere = live.contains { device in
                record.matches(address: device.address)
                    || (device.hasRealName && record.matches(name: device.name))
            }
            guard !liveHere else { continue }
            // Prefer an address already known to be a keyboard: a record can carry aliases
            // for both halves of a keyboard/mouse combo, and only the keyboard is shown.
            let address = record.addresses.first { kind(of: $0) == .keyboard }
                ?? record.addresses.first
            guard let address else { continue }
            let kind = kind(of: address)
            guard kind != .pointing else { continue }
            let name = record.name.isEmpty ? (state.knownNames[address.uppercased()] ?? address) : record.name
            devices.append(DeviceStatus(address: address, name: name,
                                        kind: kind,
                                        present: false, wanted: true, boosted: false))
        }
        devices.sort { ($0.present ? 0 : 1, $0.name.lowercased()) < ($1.present ? 0 : 1, $1.name.lowercased()) }

        let now = input.now
        state.boostedSince = anyBoosted ? (state.boostedSince ?? now) : nil

        // Signal strength every 10 s, and a history row every minute. The history is the
        // whole point: an intermittent fault has to leave a trace.
        var sampling = Sampling(readRSSI: false, recordHistory: false, measureLoss: false)
        if now.timeIntervalSince(state.lastRSSISample) >= 10 {
            state.lastRSSISample = now
            sampling.readRSSI = true
        }
        if now.timeIntervalSince(state.lastHistoryWrite) >= 60 {
            state.lastHistoryWrite = now
            // Only trust the loss figure once the link has been up for longer than the
            // window it is measured over. Otherwise the reconnect itself reads as a fault.
            sampling.measureLoss = state.boostedSince.map { now.timeIntervalSince($0) >= 70 } ?? false
            sampling.recordHistory = true
        }

        return Decision(actions: actions, learned: learned, devices: devices,
                        sampling: sampling, boosted: anyBoosted, state: state)
    }
}
