import Foundation

/// Decides when the device inventory may re-read the system's device list.
///
/// A parse is retried immediately only when a never-attempted address shows up; an address
/// that was already tried waits out the short interval, and an unchanged set is refreshed
/// periodically so a kind that changes is eventually noticed.
struct RefreshPolicy {
    var minimumInterval: TimeInterval = 60
    var maximumInterval: TimeInterval = 600
    private(set) var lastRefresh: Date = .distantPast
    private(set) var attempted: Set<String> = []
    private(set) var refreshing = false

    init() {}

    /// True when a parse should start; records it as in flight.
    mutating func begin(unknown: Set<String>, now: Date) -> Bool {
        guard !refreshing else { return false }
        let elapsed = now.timeIntervalSince(lastRefresh)
        guard !unknown.isEmpty || elapsed > maximumInterval else { return false }
        guard !unknown.isSubset(of: attempted) || elapsed > minimumInterval else { return false }
        refreshing = true
        lastRefresh = now
        attempted = unknown
        return true
    }

    /// Marks the in-flight parse as finished, whether or not it produced anything.
    mutating func finish() {
        refreshing = false
    }
}
