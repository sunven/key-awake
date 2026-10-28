import Foundation

enum Paths {
    static let support: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyAwake", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

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
        let data = Data("\(stamp)  \(message)\n".utf8)
        FileHandle.standardError.write(data)
        if let h = try? FileHandle(forWritingTo: Paths.log) {
            defer { try? h.close() }
            // Truncate past 1 MB so it cannot grow forever.
            if (try? h.seekToEnd()) ?? 0 > 1_000_000 {
                try? data.write(to: Paths.log, options: .atomic)
                return
            }
            h.write(data)
        } else {
            try? data.write(to: Paths.log, options: .atomic)
        }
    }
}
