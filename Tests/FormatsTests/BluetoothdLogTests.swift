import XCTest
@testable import KeyAwakeCore

final class BluetoothdLogTests: XCTestCase {
    func testSumsCounterLines() {
        let text = """
        rx [S=  12:F=   3]
        rx [S= 8:F=1]
        """
        XCTAssertEqual(BluetoothdLog.counters(from: text), LinkCounters(succeeded: 20, failed: 4))
    }

    func testIgnoresLinesWithoutCounters() {
        let text = """
        2026-01-01 something else
        rx [S= 5:F=2]
        """
        XCTAssertEqual(BluetoothdLog.counters(from: text), LinkCounters(succeeded: 5, failed: 2))
    }

    func testMalformedCountersAreIgnored() {
        let text = "rx [S= 5]\nrx [S= 7:F=1]"
        XCTAssertEqual(BluetoothdLog.counters(from: text), LinkCounters(succeeded: 7, failed: 1))
    }

    func testLossIsNilBelowThreshold() {
        XCTAssertNil(LinkCounters(succeeded: 199, failed: 0).lossPercent())
    }

    func testLossPercentAtThreshold() {
        XCTAssertEqual(LinkCounters(succeeded: 190, failed: 10).lossPercent(), 5.0)
    }

    func testZeroFailuresIsZeroPercent() {
        XCTAssertEqual(LinkCounters(succeeded: 200, failed: 0).lossPercent(), 0.0)
    }

    func testMinimumPacketsIsConfigurable() {
        XCTAssertEqual(LinkCounters(succeeded: 9, failed: 1).lossPercent(minimumPackets: 10), 10.0)
        XCTAssertNil(LinkCounters(succeeded: 9, failed: 1).lossPercent(minimumPackets: 11))
    }
}
