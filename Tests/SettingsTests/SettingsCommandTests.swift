import XCTest
@testable import KeyAwakeCore

final class SettingsCommandTests: XCTestCase {
    private func settings(boosted: [BoostedDevice] = []) -> Settings {
        var value = Settings()
        value.boosted = boosted
        return value
    }

    func testSetEnabled() {
        var value = settings()
        XCTAssertTrue(value.apply(.setEnabled(false)))
        XCTAssertFalse(value.enabled)
        XCTAssertFalse(value.apply(.setEnabled(false)))
    }

    func testSetShowMenuBarIcon() {
        var value = settings()
        XCTAssertTrue(value.apply(.setShowMenuBarIcon(true)))
        XCTAssertTrue(value.showMenuBarIcon)
        XCTAssertFalse(value.apply(.setShowMenuBarIcon(true)))
    }

    func testSetLatencyLevel() {
        var value = settings()
        XCTAssertTrue(value.apply(.setLatencyLevel(2)))
        XCTAssertEqual(value.latencyLevel, 2)
        XCTAssertFalse(value.apply(.setLatencyLevel(2)))
    }

    func testSetIdleReleaseSeconds() {
        var value = settings()
        XCTAssertTrue(value.apply(.setIdleReleaseSeconds(0)))
        XCTAssertEqual(value.idleReleaseSeconds, 0)
        XCTAssertFalse(value.apply(.setIdleReleaseSeconds(0)))
    }

    func testStartDeviceStoresRealName() {
        var value = settings()
        XCTAssertTrue(value.apply(.startDevice(address: "AA", name: "K", nameIsReal: true)))
        XCTAssertEqual(value.boosted, [BoostedDevice(name: "K", addresses: ["AA"])])
        XCTAssertFalse(value.apply(.startDevice(address: "AA", name: "K", nameIsReal: true)))
    }

    func testStartDeviceNeverStoresPlaceholderName() {
        var value = settings()
        XCTAssertTrue(value.apply(.startDevice(address: "AA", name: "Device 12345", nameIsReal: false)))
        XCTAssertEqual(value.boosted, [BoostedDevice(name: "", addresses: ["AA"])])
    }

    func testForgetDeviceRemovesEveryAlias() {
        var value = settings(boosted: [BoostedDevice(name: "K", addresses: ["AA", "BB"])])
        XCTAssertTrue(value.apply(.forgetDevice(address: "AA", name: "K")))
        XCTAssertTrue(value.boosted.isEmpty)
    }

    func testForgetDeviceMatchesByName() {
        var value = settings(boosted: [BoostedDevice(name: "K", addresses: ["AA"])])
        XCTAssertTrue(value.apply(.forgetDevice(address: "ZZ", name: "K")))
        XCTAssertTrue(value.boosted.isEmpty)
    }

    func testForgetUnknownDeviceIsANoOp() {
        var value = settings(boosted: [BoostedDevice(name: "K", addresses: ["AA"])])
        XCTAssertFalse(value.apply(.forgetDevice(address: "ZZ", name: "Other")))
        XCTAssertEqual(value.boosted, [BoostedDevice(name: "K", addresses: ["AA"])])
    }

    func testCommandsRoundTripThroughJSON() throws {
        let commands: [SettingsCommand] = [
            .setEnabled(false),
            .setShowMenuBarIcon(true),
            .setLatencyLevel(1),
            .setIdleReleaseSeconds(600),
            .startDevice(address: "AA", name: "K", nameIsReal: true),
            .forgetDevice(address: "AA", name: "K"),
        ]
        for command in commands {
            let data = try JSONEncoder().encode(command)
            XCTAssertEqual(try JSONDecoder().decode(SettingsCommand.self, from: data), command)
        }
    }
}
