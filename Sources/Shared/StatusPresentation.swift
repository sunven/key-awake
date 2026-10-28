import Foundation

/// Decides what the interface and the menu bar tell the user.
///
/// The precedence lives here so the two surfaces cannot disagree: one order for engine
/// liveness, Bluetooth state, API availability, and boost activity.
enum StatusPresentation {
    enum EngineLiveness: Equatable {
        case alive
        case absent(launchAtLogin: Bool)
    }

    enum State: Equatable {
        case disabled, stopped, boosting, idle
    }

    enum Tone: Equatable {
        case neutral, positive, attention
    }

    struct Presentation: Equatable {
        let state: State
        let problem: String?
        let tone: Tone
        let symbol: String
        let shortHeadline: String
        let menuHeadline: String
    }

    static func describe(settings: Settings, status: AgentStatus,
                         liveness: EngineLiveness) -> Presentation {
        let problem = problem(status: status, liveness: liveness)

        let state: State
        if !settings.enabled {
            state = .disabled
        } else if problem != nil {
            state = .stopped
        } else {
            state = status.active ? .boosting : .idle
        }

        let tone: Tone
        switch state {
        case .disabled, .stopped: tone = .neutral
        case .boosting:           tone = .positive
        case .idle:               tone = .attention
        }

        let symbol: String
        switch state {
        case .disabled, .stopped: symbol = "bolt.slash"
        case .boosting:           symbol = "bolt.fill"
        case .idle:               symbol = "bolt"
        }

        let shortHeadline: String
        switch state {
        case .disabled: shortHeadline = L("Disabled")
        case .stopped:  shortHeadline = L("Stopped")
        case .boosting: shortHeadline = L("Boosting")
        case .idle:     shortHeadline = L("Idle")
        }

        let menuHeadline: String
        switch state {
        case .disabled: menuHeadline = L("KeyAwake — disabled")
        case .stopped:  menuHeadline = problem ?? L("Stopped")
        case .boosting: menuHeadline = L("KeyAwake — boosting")
        case .idle:     menuHeadline = L("KeyAwake — idle")
        }

        return Presentation(state: state, problem: problem, tone: tone, symbol: symbol,
                            shortHeadline: shortHeadline, menuHeadline: menuHeadline)
    }

    private static func problem(status: AgentStatus, liveness: EngineLiveness) -> String? {
        // A stale status file says nothing about Bluetooth: asking about Bluetooth first made
        // a dead engine show up as "Bluetooth state unknown."
        switch liveness {
        case .absent(let launchAtLogin):
            return launchAtLogin
                ? L("The engine is not responding. Try turning “Start at login” off and on again.")
                : L("The engine is not running. Reopen KeyAwake to start it.")
        case .alive:
            if let issue = status.bluetooth.problem { return issue }
            if !status.apiAvailable {
                return L("This version of macOS no longer exposes the latency setting. KeyAwake cannot help.")
            }
            return nil
        }
    }

    /// Per-device status text, in a list row or the menu bar.
    static func detail(for device: DeviceStatus, enabled: Bool) -> String {
        if !device.present { return L("away") }
        if device.kind != .keyboard { return L("not supported") }
        if !device.wanted { return "—" }
        if !enabled { return L("off") }
        return device.boosted ? L("latency 0") : L("idle")
    }
}
