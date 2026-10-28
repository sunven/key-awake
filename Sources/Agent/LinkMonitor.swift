import Foundation

/// Keeps a rolling record of how well the link is actually working.
///
/// The point is not to fix anything — it is so that an intermittent fault leaves a trace.
/// Diagnosing one from a snapshot taken an hour later means blaming whatever happens to be
/// different, which is how you end up accusing a USB dock that turns out to be innocent.
///
/// RSSI comes from CoreBluetooth. Packet loss is not exposed by any public API, so it is
/// parsed out of `bluetoothd`'s own per-second link statistics. That costs about 0.9 s of
/// CPU once a minute, measured — roughly 0.2 % of one core.
final class LinkMonitor {
    struct Quality {
        var rssi: Int?
        var lossPercent: Double?
        var radioCyclesLastHour: Int = 0
    }

    private(set) var current = Quality()
    private var sampling = false
    private let queue = DispatchQueue(label: "keyawake.linkmonitor")
    private let history = LinkHistory()
    private var radioChanges: [Date] = []

    /// Call whenever the Bluetooth radio changes state; the count feeds the diagnosis.
    func noteRadioStateChange() {
        let now = Date()
        radioChanges.append(now)
        radioChanges.removeAll { now.timeIntervalSince($0) > 3600 }
        current.radioCyclesLastHour = radioChanges.count
    }

    func noteRSSI(_ value: Int) { current.rssi = value }

    /// Reads the last minute of link statistics and appends a row to the history.
    /// - Parameter measureLoss: false while the link is too freshly established for the
    ///   figure to mean anything. The reading is cleared rather than left stale.
    func sampleAndRecord(boosted: Bool, measureLoss: Bool, bluetooth: String, deviceName: String) {
        queue.async { [weak self] in
            guard let self, !self.sampling else { return }
            self.sampling = true
            defer { self.sampling = false }

            if measureLoss {
                if let loss = Self.readPacketLoss() { self.current.lossPercent = loss }
            } else {
                self.current.lossPercent = nil
            }
            self.history.append(LinkSample(at: Date(),
                                           rssi: self.current.rssi,
                                           lossPercent: self.current.lossPercent,
                                           boosted: boosted,
                                           bluetooth: bluetooth,
                                           radioCyclesLastHour: self.current.radioCyclesLastHour,
                                           deviceName: deviceName))
        }
    }

    /// Sums the success/failure counters bluetoothd prints once a second per LE link.
    private static func readPacketLoss() -> Double? {
        guard let data = ProcessRunner.output("/usr/bin/log",
                                              ["show", "--last", "65s", "--debug", "--style", "compact",
                                               "--predicate", #"process == "bluetoothd" AND category == "Server.Core""#]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return BluetoothdLog.counters(from: text).lossPercent()
    }
}
