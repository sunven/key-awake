import XCTest
@testable import KeyAwakeCore

final class LinkHistoryTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyawake-history-\(UUID().uuidString).csv")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func sample(at: Date = Date(timeIntervalSince1970: 1_000_000),
                        rssi: Int? = -50, loss: Double? = 1.5, boosted: Bool = true,
                        bluetooth: String = "on", cycles: Int = 0,
                        device: String = "K") -> LinkSample {
        LinkSample(at: at, rssi: rssi, lossPercent: loss, boosted: boosted,
                   bluetooth: bluetooth, radioCyclesLastHour: cycles, deviceName: device)
    }

    private func lines() -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private func fields(of line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    func testFirstSampleWritesHeaderAndRow() {
        let at = Date(timeIntervalSince1970: 1_000_000)
        LinkHistory(url: url).append(sample(at: at))

        let lines = lines()
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "timestamp,rssi_dbm,loss_pct,boosted,bluetooth,radio_cycles_1h,device")
        XCTAssertEqual(fields(of: lines[1]),
                       [ISO8601DateFormatter().string(from: at), "-50", "1.5", "true", "on", "0", "K"])
    }

    func testNilReadingsBecomeEmptyFields() {
        LinkHistory(url: url).append(sample(rssi: nil, loss: nil, boosted: false))

        let parts = fields(of: lines()[1])
        XCTAssertEqual(parts[1], "")
        XCTAssertEqual(parts[2], "")
        XCTAssertEqual(parts[3], "false")
    }

    func testRowsAreAppended() {
        let history = LinkHistory(url: url)
        history.append(sample(device: "A"))
        history.append(sample(device: "B"))

        let lines = lines()
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasSuffix(",A"))
        XCTAssertTrue(lines[2].hasSuffix(",B"))
    }

    func testTrimKeepsTheHeaderAndTheNewestRows() {
        let history = LinkHistory(url: url, maxBytes: 1)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<5 {
            history.append(sample(at: base.addingTimeInterval(Double(index)), device: "D\(index)"))
        }

        let lines = lines()
        XCTAssertEqual(lines[0], "timestamp,rssi_dbm,loss_pct,boosted,bluetooth,radio_cycles_1h,device")
        XCTAssertFalse(lines.contains { $0.hasSuffix(",D0") })
        XCTAssertTrue(lines.last?.hasSuffix(",D4") ?? false)
    }
}
