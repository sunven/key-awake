import AppKit
import Foundation

/// Starting the engine automatically, via a LaunchAgent.
enum LoginItem {
    /// The bundle identifier `build.sh` gives the nested engine.
    private static let agentIdentifier = "com.keyawake.agent"

    /// The engine is nested inside the main bundle, like any macOS login item, so the app
    /// ships as a single thing you drag to Applications.
    static var agentApp: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/KeyAwakeAgent.app")
    }

    static var agentExecutable: URL {
        agentApp.appendingPathComponent("Contents/MacOS/KeyAwakeAgent")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: Paths.launchAgentPlist.path)
    }

    /// An engine started by launchd, or one started for this session by the interface.
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: agentIdentifier).isEmpty
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let plist = Paths.launchAgentPlist
        let uid = getuid()
        if enabled {
            let contents: [String: Any] = [
                "Label": Paths.launchAgentLabel,
                "ProgramArguments": [agentExecutable.path],
                "RunAtLoad": true,
                "KeepAlive": true,
                "ProcessType": "Interactive",
            ]
            try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            guard let data = try? PropertyListSerialization.data(fromPropertyList: contents,
                                                                 format: .xml, options: 0),
                  (try? data.write(to: plist, options: .atomic)) != nil else { return false }
            launchctl(["bootout", "gui/\(uid)/\(Paths.launchAgentLabel)"])   // por si ya estaba
            stopSessionAgent()
            return launchctl(["bootstrap", "gui/\(uid)", plist.path])
        } else {
            launchctl(["bootout", "gui/\(uid)/\(Paths.launchAgentLabel)"])
            try? FileManager.default.removeItem(at: plist)
            return true
        }
    }

    /// Starts the engine right away if it is not running, so you need not log out and back in.
    ///
    /// Without a login item there is no launchd job to kick, and a window with no engine is
    /// useless: it cannot list devices or say anything about Bluetooth. A first run has no
    /// login item yet, so the engine is started for this session instead. It outlives the
    /// window; “Start at login” is what makes it outlive a restart.
    static func startAgentIfNeeded() {
        guard !isRunning else { return }
        if isEnabled {
            launchctl(["kickstart", "gui/\(getuid())/\(Paths.launchAgentLabel)"])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: agentApp, configuration: configuration) { _, error in
            if let error { Log.write("no se pudo arrancar el motor: \(error.localizedDescription)") }
        }
    }

    /// Ends the engine launchd is not managing, so enabling the login item afterwards
    /// cannot leave two engines holding the same peripherals.
    private static func stopSessionAgent() {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: agentIdentifier)
        guard !instances.isEmpty else { return }
        for instance in instances { instance.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, instances.contains(where: { !$0.isTerminated }) {
            usleep(50_000)
        }
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Bool {
        ProcessRunner.run("/bin/launchctl", arguments)
    }
}
