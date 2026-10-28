import Foundation

/// An intent from the interface to the engine. The engine is the only writer of settings.
enum SettingsCommand: Codable, Equatable {
    case setEnabled(Bool)
    case setShowMenuBarIcon(Bool)
    case setLatencyLevel(Int)
    case setIdleReleaseSeconds(Int)
    case startDevice(address: String, name: String, nameIsReal: Bool)
    case forgetDevice(address: String, name: String)
}

extension Settings {
    /// Applies one command. True only when the record actually changed.
    @discardableResult
    mutating func apply(_ command: SettingsCommand) -> Bool {
        switch command {
        case .setEnabled(let enabled):
            guard self.enabled != enabled else { return false }
            self.enabled = enabled
        case .setShowMenuBarIcon(let show):
            guard showMenuBarIcon != show else { return false }
            showMenuBarIcon = show
        case .setLatencyLevel(let level):
            guard latencyLevel != level else { return false }
            latencyLevel = level
        case .setIdleReleaseSeconds(let seconds):
            guard idleReleaseSeconds != seconds else { return false }
            idleReleaseSeconds = seconds
        case .startDevice(let address, let name, let nameIsReal):
            guard !boosts(address: address) else { return false }
            start(address: address, name: name, nameIsReal: nameIsReal)
        case .forgetDevice(let address, let name):
            let count = boosted.count
            forget(address: address, name: name)
            guard boosted.count != count else { return false }
        }
        return true
    }
}
