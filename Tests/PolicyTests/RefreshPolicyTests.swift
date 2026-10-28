import XCTest
@testable import KeyAwakeCore

final class RefreshPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testFirstUnknownAddressStartsAParse() {
        var policy = RefreshPolicy()
        XCTAssertTrue(policy.begin(unknown: ["AA"], now: start))
        XCTAssertTrue(policy.refreshing)
    }

    func testRefreshingBlocksAnotherParse() {
        var policy = RefreshPolicy()
        XCTAssertTrue(policy.begin(unknown: ["AA"], now: start))
        XCTAssertFalse(policy.begin(unknown: ["AA", "BB"], now: start.addingTimeInterval(1)))
        policy.finish()
        XCTAssertTrue(policy.begin(unknown: ["AA", "BB"], now: start.addingTimeInterval(2)))
    }

    func testSameUnknownWaitsForTheMinimumInterval() {
        var policy = RefreshPolicy()
        XCTAssertTrue(policy.begin(unknown: ["AA"], now: start))
        policy.finish()
        XCTAssertFalse(policy.begin(unknown: ["AA"], now: start.addingTimeInterval(60)))
        XCTAssertTrue(policy.begin(unknown: ["AA"], now: start.addingTimeInterval(61)))
    }

    func testNewUnknownStartsImmediately() {
        var policy = RefreshPolicy()
        XCTAssertTrue(policy.begin(unknown: ["AA"], now: start))
        policy.finish()
        XCTAssertTrue(policy.begin(unknown: ["AA", "BB"], now: start.addingTimeInterval(1)))
    }

    func testEmptyUnknownWaitsForTheMaximumInterval() {
        var policy = RefreshPolicy()
        XCTAssertTrue(policy.begin(unknown: ["AA"], now: start))
        policy.finish()
        XCTAssertFalse(policy.begin(unknown: [], now: start.addingTimeInterval(600)))
        XCTAssertTrue(policy.begin(unknown: [], now: start.addingTimeInterval(601)))
    }

    func testFinishAllowsTheNextParse() {
        var policy = RefreshPolicy()
        XCTAssertTrue(policy.begin(unknown: ["AA"], now: start))
        policy.finish()
        XCTAssertFalse(policy.refreshing)
    }
}
