import Foundation

/// Reads device kinds out of `system_profiler SPBluetoothDataType`.
///
/// CoreBluetooth will not say, and `system_profiler` is the only source. The parse is kept
/// pure so a macOS format change fails a test instead of silently classifying nothing.
enum SystemProfiler {
    static func kinds(from text: String) -> [String: DeviceKind] {
        // Within each device block, "Address:" comes before "Minor Type:".
        var result: [String: DeviceKind] = [:]
        var current: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Address:") {
                current = line.dropFirst("Address:".count)
                    .trimmingCharacters(in: .whitespaces).uppercased()
            } else if line.hasPrefix("Minor Type:"), let address = current {
                let value = line.dropFirst("Minor Type:".count).trimmingCharacters(in: .whitespaces).lowercased()
                if value.contains("keyboard") {
                    result[address] = .keyboard
                } else if value.contains("mouse") || value.contains("trackpad") || value.contains("pointing") {
                    result[address] = .pointing
                } else {
                    result[address] = .other
                }
                current = nil
            }
        }
        return result
    }
}
