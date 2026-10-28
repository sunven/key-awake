import Foundation

enum Paths {
    static let support: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyAwake", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        migrateFromKeyBoost(into: base)
        return base
    }()

    /// The app was called KeyBoost up to 1.1.1, with its own support folder. Copying the two
    /// files that hold user state means an upgrade keeps the configured keyboards instead of
    /// silently reverting them to the 345 ms fault. The old folder is left untouched.
    private static func migrateFromKeyBoost(into base: URL) {
        let fileManager = FileManager.default
        let old = base.deletingLastPathComponent()
            .appendingPathComponent("KeyBoost", isDirectory: true)
        for name in ["settings.json", "link-history.csv"] {
            let source = old.appendingPathComponent(name)
            let destination = base.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.copyItem(at: source, to: destination)
        }
    }

    static var settings: URL { support.appendingPathComponent("settings.json") }
    static var status:   URL { support.appendingPathComponent("status.json") }
    static var log:      URL { support.appendingPathComponent("keyawake.log") }
    static var history:  URL { support.appendingPathComponent("link-history.csv") }

    static let launchAgentLabel = "com.keyawake.agent"
    static var launchAgentPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }
}

/// Atomic writes, forgiving reads. Corrupt JSON must never take a process down.
enum JSONStore {
    static func write<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }
}

enum Log {
    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: Paths.log) {
            defer { try? h.close() }
            // Truncate past 1 MB so it cannot grow forever.
            if (try? h.seekToEnd()) ?? 0 > 1_000_000 {
                try? Data().write(to: Paths.log, options: .atomic)
                try? data.write(to: Paths.log, options: .atomic)
                return
            }
            h.write(data)
        } else {
            try? data.write(to: Paths.log, options: .atomic)
        }
    }
}
