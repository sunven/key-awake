import Foundation

struct LinkCounters: Equatable {
    var succeeded = 0
    var failed = 0
    var total: Int { succeeded + failed }

    /// A percentage over a handful of packets is noise, not a measurement. While nobody is
    /// typing the link carries almost nothing, and 11 failures out of 14 reads as 79 % when
    /// it means nothing at all. Below the threshold, report no figure rather than a
    /// frightening one.
    func lossPercent(minimumPackets: Int = 200) -> Double? {
        total >= minimumPackets ? Double(failed) * 100 / Double(total) : nil
    }
}

/// Sums the success/failure counters bluetoothd prints once a second per LE link.
enum BluetoothdLog {
    static func counters(from text: String) -> LinkCounters {
        var counters = LinkCounters()
        for line in text.split(separator: "\n") {
            // Format: rx [S=  12:F=   3]
            guard let range = line.range(of: "rx [S=") else { continue }
            let tail = line[range.upperBound...]
            let numbers = tail.prefix(20).split(whereSeparator: { !"0123456789".contains($0) })
            if numbers.count >= 2, let succeeded = Int(numbers[0]), let failed = Int(numbers[1]) {
                counters.succeeded += succeeded
                counters.failed += failed
            }
        }
        return counters
    }
}
