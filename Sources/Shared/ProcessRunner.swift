import Foundation

/// Runs the command-line tools that have no API equivalent: `launchctl` for the login item,
/// `system_profiler` for device kinds, and `log show` for packet loss.
enum ProcessRunner {
    /// Standard output, or nil when the tool could not be started.
    static func output(_ executable: String, _ arguments: [String]) -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return data
    }

    /// True when the tool started and exited with status 0.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
