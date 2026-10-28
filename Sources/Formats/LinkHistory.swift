import Foundation

/// One per-minute reading of link health, as written to History.
struct LinkSample {
    var at: Date
    var rssi: Int?
    var lossPercent: Double?
    var boosted: Bool
    var bluetooth: String
    var radioCyclesLastHour: Int
    var deviceName: String
}

/// The CSV history of link health.
///
/// The format is a contract: the file is what makes an intermittent fault diagnosable later.
/// Writing is synchronous; the caller serialises it (LinkMonitor's sampling queue).
struct LinkHistory {
    private static let header = "timestamp,rssi_dbm,loss_pct,boosted,bluetooth,radio_cycles_1h,device\n"

    private let url: URL
    private let maxBytes: Int

    init(url: URL = Paths.history, maxBytes: Int = 2_000_000) {
        self.url = url
        self.maxBytes = maxBytes
    }

    func append(_ sample: LinkSample) {
        let formatter = ISO8601DateFormatter()
        let rssi = sample.rssi.map(String.init) ?? ""
        let loss = sample.lossPercent.map { String(format: "%.1f", $0) } ?? ""
        let row = "\(formatter.string(from: sample.at)),\(rssi),\(loss),\(sample.boosted),\(sample.bluetooth),\(sample.radioCyclesLastHour),\(sample.deviceName)\n"

        if !FileManager.default.fileExists(atPath: url.path) {
            try? (Self.header + row).write(to: url, atomically: true, encoding: .utf8)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        handle.write(Data(row.utf8))
        if size > UInt64(maxBytes) { trim() }   // keep roughly the last two weeks
    }

    /// Drops the oldest half so the file cannot grow without bound.
    private func trim() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 4 else { return }
        let header = lines.removeFirst()
        lines.removeFirst(lines.count / 2)
        try? (header + "\n" + lines.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
    }
}
