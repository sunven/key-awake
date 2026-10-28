import Combine
import Foundation
import SwiftUI

/// Bridge between the shared files and the view.
final class Model: ObservableObject {
    @Published var settings: Settings = .load()
    @Published var status: AgentStatus = .load()
    @Published var launchAtLogin: Bool = LoginItem.isEnabled

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init() {
        observers.append(IPC.observe(.statusChanged) { [weak self] in
            self?.status = .load()
        })
        // The engine is the only writer; its broadcast is the authoritative settings update.
        observers.append(IPC.observe(.settingsChanged) { [weak self] in
            self?.settings = .load()
        })
        // Safety net for the status heartbeat; settings arrive by notification.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.status = .load()
        }
    }

    /// Applies a command locally so the window reacts at once, then lets the engine own the write.
    func edit(_ command: SettingsCommand) {
        var copy = settings
        let changed = copy.apply(command)
        settings = copy
        if LoginItem.isRunning {
            IPC.send(command)
        } else if changed {
            copy.save()
        }
    }

    func setBoosted(_ device: DeviceStatus, _ on: Bool) {
        if on {
            edit(.startDevice(address: device.address, name: device.name,
                              nameIsReal: !device.name.isEmpty && device.name != device.address))
        } else {
            edit(.forgetDevice(address: device.address, name: device.name))
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.setEnabled(on)
        launchAtLogin = LoginItem.isEnabled
    }

    /// What the window should say, from the one module that decides it.
    private var presentation: StatusPresentation.Presentation {
        let liveness: StatusPresentation.EngineLiveness =
            status.agentAlive ? .alive : .absent(launchAtLogin: launchAtLogin)
        return StatusPresentation.describe(settings: settings, status: status, liveness: liveness)
    }

    /// What the user needs to be told, if anything.
    var problem: String? { presentation.problem }

    var headline: String { presentation.shortHeadline }

    var symbol: String { presentation.symbol }

    var isBoosting: Bool { presentation.state == .boosting }

    var stateColor: Color {
        switch presentation.tone {
        case .neutral:   return .secondary
        case .positive:  return .green
        case .attention: return .orange
        }
    }

    var latencyChoice: Settings.LatencyChoice? {
        Settings.latencyChoices.first { $0.level == settings.latencyLevel }
    }

    /// The line under the latency picker: "… interval · worst case ~N ms".
    var latencyDetail: String? {
        guard let choice = latencyChoice else { return nil }
        return L("%@ · worst case ~%d ms", choice.detail, choice.worstCaseMs)
    }

    /// A warning sized to the risk: the highest level is literally worse than not using the app.
    var latencyWarning: String? {
        guard let choice = latencyChoice, !choice.isSafe else { return nil }
        return choice.level == 2
            ? L("Worst case ~%d ms instead of 30. That is slower than the bug KeyAwake fixes (345 ms), so your keyboard will be worse off than without the app.", choice.worstCaseMs)
            : L("Worst case ~%d ms instead of 30. Noticeable while typing, but easier on the battery.", choice.worstCaseMs)
    }

    var healthLabel: String {
        switch status.health {
        case .good: return L("Good")
        case .fair: return L("Fair")
        case .poor: return L("Poor")
        case .unknown: return "—"
        }
    }

    var healthColor: Color {
        switch status.health {
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        case .unknown: return .secondary
        }
    }

    var signalText: String {
        guard let rssi = status.rssi else { return L("not measured while idle") }
        return "\(rssi) dBm"
    }

    var lossText: String {
        guard let loss = status.lossPercent else { return L("too little traffic to measure") }
        return String(format: "%.1f %%", loss)
    }
}
