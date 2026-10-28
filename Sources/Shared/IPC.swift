import Foundation

/// Messages between the app and the engine. DistributedNotificationCenter is enough:
/// both processes run in the same user session and neither is sandboxed.
enum IPC {
    enum Name: String {
        case settingsChanged = "com.keyawake.settings-changed"
        case statusChanged   = "com.keyawake.status-changed"
        case settingsCommand = "com.keyawake.settings-command"
    }

    static func post(_ name: Name) {
        DistributedNotificationCenter.default()
            .postNotificationName(Notification.Name(name.rawValue), object: nil,
                                  userInfo: nil, deliverImmediately: true)
    }

    static func observe(_ name: Name, handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default()
            .addObserver(forName: Notification.Name(name.rawValue), object: nil, queue: .main) { _ in
                handler()
            }
    }

    /// Sends one settings intent to the engine.
    static func send(_ command: SettingsCommand) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        DistributedNotificationCenter.default()
            .postNotificationName(Notification.Name(Name.settingsCommand.rawValue), object: nil,
                                  userInfo: ["command": data], deliverImmediately: true)
    }

    /// Receives settings intents on the main queue. Malformed payloads are ignored.
    static func observeCommands(_ handler: @escaping (SettingsCommand) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default()
            .addObserver(forName: Notification.Name(Name.settingsCommand.rawValue),
                         object: nil, queue: .main) { notification in
                guard let data = notification.userInfo?["command"] as? Data,
                      let command = try? JSONDecoder().decode(SettingsCommand.self, from: data)
                else { return }
                handler(command)
            }
    }
}
