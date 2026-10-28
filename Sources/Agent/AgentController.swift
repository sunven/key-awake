import AppKit
import Foundation

/// Ties everything together: reads settings, decides boost or idle, publishes status.
final class AgentController {
    private let engine = BluetoothEngine()
    private let inventory = DeviceInventory()
    private let monitor = LinkMonitor()
    private var menuBar: MenuBarController?

    private var settings = Settings.load()
    private var lastPublished: AgentStatus?
    private var lastWrite: Date = .distantPast
    private var policyState = BoostPolicy.State(boostedSince: nil)
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var settingsStamp: Date?

    func start() {
        // Names of absent devices, so they are not shown as "unknown".
        for device in AgentStatus.load().devices {
            policyState.knownNames[device.address.uppercased()] = device.name
        }

        observers.append(IPC.observeCommands { [weak self] command in
            self?.apply(command)
        })

        // Sleeping releases the links: boosting a closed laptop makes no sense.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Log.write("el Mac se duerme, soltando enlaces")
            self?.engine.releaseAll()
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            // macOS reapplies its own LEHID profile across sleep, so the request has to go
            // out again at once. Without clearing the throttle the keyboard would sit on
            // latency 22 for up to 30 seconds after every wake.
            Log.write("el Mac despierta, reaplicando latencia")
            self?.engine.invalidateRequests()
            self?.tick()
        })

        engine.latencyLevel = settings.latencyLevel
        settingsStamp = Self.settingsModified()
        engine.onRSSI = { [weak self] value in self?.monitor.noteRSSI(value) }
        engine.onRadioStateChange = { [weak self] in self?.monitor.noteRadioStateChange() }
        engine.onStateChange = { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        syncMenuBar()
        // The first reading goes out now, not with the first timer tick: until it lands the
        // interface can only conclude that the engine is not running.
        tick()
        Log.write("motor arrancado")
    }

    /// Applies one settings intent. The engine is the only writer: save once, then propagate.
    private func apply(_ command: SettingsCommand) {
        let previousLevel = settings.latencyLevel
        guard settings.apply(command) else { return }

        settings.save()
        settingsStamp = Self.settingsModified()
        engine.latencyLevel = settings.latencyLevel
        if previousLevel != settings.latencyLevel { engine.invalidateRequests() }
        Log.write("ajustes: activado=\(settings.enabled) barra=\(settings.showMenuBarIcon) "
                  + "reposo=\(settings.idleReleaseSeconds)s latencia=\(settings.latencyLevel)")

        // The menu bar may remove itself in response to this command; deferring keeps the
        // controller alive until the current menu action returns.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncMenuBar()
            self.tick()
        }
    }

    /// Re-reads settings and propagates whatever changed.
    private func reloadSettings() {
        let previousLevel = settings.latencyLevel
        settings = Settings.load()
        settingsStamp = Self.settingsModified()
        engine.latencyLevel = settings.latencyLevel
        if previousLevel != settings.latencyLevel { engine.invalidateRequests() }
        Log.write("ajustes: activado=\(settings.enabled) barra=\(settings.showMenuBarIcon) "
                  + "reposo=\(settings.idleReleaseSeconds)s latencia=\(settings.latencyLevel)")
        syncMenuBar()
        tick()
    }

    private static func settingsModified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Paths.settings.path))?[.modificationDate] as? Date
    }

    /// Safety net: if the file changes without a notification (hand-edited, restored from
    /// a backup), the engine still notices on the next tick and tells the interface.
    private func reloadSettingsIfFileChanged() {
        guard Self.settingsModified() != settingsStamp else { return }
        reloadSettings()
        IPC.post(.settingsChanged)
    }

    private func syncMenuBar() {
        if settings.showMenuBarIcon {
            if menuBar == nil {
                menuBar = MenuBarController(
                    onToggleEnabled: { [weak self] in
                        guard let self else { return }
                        self.apply(.setEnabled(!self.settings.enabled))
                    },
                    onHideIcon: { [weak self] in
                        guard let self else { return }
                        self.apply(.setShowMenuBarIcon(false))
                    })
            }
        } else {
            menuBar = nil
        }
    }

    private func tick() {
        reloadSettingsIfFileChanged()

        let live = engine.liveDevices()
        inventory.refreshIfNeeded(addresses: live.map(\.address))

        // Every address the policy may ask about, resolved once per tick.
        var kinds: [String: DeviceKind] = [:]
        for device in live {
            kinds[device.address.uppercased()] = inventory.kind(for: device.address)
        }
        for record in settings.boosted {
            for alias in record.addresses {
                let key = alias.uppercased()
                if kinds[key] == nil { kinds[key] = inventory.kind(for: alias) }
            }
        }

        let connected = Set(live.filter { $0.peripheral.state == .connected }
                                .map { $0.address.uppercased() })
        let idleLimit = settings.idleReleaseSeconds
        let idleSeconds = idleLimit == 0 ? 0 : ActivityMonitor.keyboardIdleSeconds()

        let input = BoostPolicy.Input(
            settings: settings,
            live: live.map { ObservedDevice(address: $0.address, name: $0.name,
                                            hasRealName: $0.hasRealName) },
            kinds: kinds,
            connected: connected,
            idleSeconds: idleSeconds,
            now: Date())
        let decision = BoostPolicy.decide(policyState, input)
        policyState = decision.state

        let liveByAddress = Dictionary(live.map { ($0.address.uppercased(), $0) },
                                       uniquingKeysWith: { first, _ in first })
        for action in decision.actions {
            switch action {
            case .boost(let address):
                if let device = liveByAddress[address.uppercased()] { engine.boost(device) }
            case .release(let address):
                engine.release(address)
            }
        }

        // One write per tick, not one per device: each save costs a file write, a
        // notification, a reload and a recursive tick.
        if !decision.learned.isEmpty {
            for identity in decision.learned {
                if settings.learn(address: identity.address, name: identity.name,
                                  nameIsReal: identity.hasRealName) {
                    Log.write("aprendida identidad de \(identity.name): \(identity.address)")
                }
            }
            settings.save()
            settingsStamp = Self.settingsModified()
        }

        if decision.sampling.readRSSI { engine.sampleRSSI() }
        if decision.sampling.recordHistory {
            monitor.sampleAndRecord(boosted: decision.boosted,
                                    measureLoss: decision.sampling.measureLoss,
                                    bluetooth: engine.state.rawValue,
                                    deviceName: decision.devices.first(where: \.boosted)?.name ?? "-")
        }

        publish(AgentStatus(bluetooth: engine.state, active: decision.boosted,
                            apiAvailable: engine.apiAvailable, devices: decision.devices,
                            rssi: monitor.current.rssi,
                            lossPercent: monitor.current.lossPercent,
                            radioCyclesLastHour: monitor.current.radioCyclesLastHour,
                            updated: input.now))
    }

    /// Writes only when something changed, or every 5 s so the interface knows we are alive.
    private func publish(_ status: AgentStatus) {
        var changed = true
        if var previous = lastPublished {
            previous.updated = status.updated
            changed = previous != status
        }
        guard changed || Date().timeIntervalSince(lastWrite) >= AgentStatus.heartbeatInterval else { return }
        status.save()
        lastPublished = status
        lastWrite = Date()
        menuBar?.update(status: status, settings: settings)
    }
}
