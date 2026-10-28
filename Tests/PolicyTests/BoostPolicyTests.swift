import XCTest
@testable import KeyAwakeCore

final class BoostPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func state(boostedSince: Date? = nil,
                       lastRSSI: Date = .distantPast,
                       lastHistory: Date = .distantPast,
                       knownNames: [String: String] = [:]) -> BoostPolicy.State {
        BoostPolicy.State(boostedSince: boostedSince, lastRSSISample: lastRSSI,
                          lastHistoryWrite: lastHistory, knownNames: knownNames)
    }

    private func settings(enabled: Bool = true, idle: Int = 180,
                          boosted: [BoostedDevice] = []) -> Settings {
        var value = Settings()
        value.enabled = enabled
        value.idleReleaseSeconds = idle
        value.boosted = boosted
        return value
    }

    private func identity(_ name: String, _ addresses: [String]) -> BoostedDevice {
        BoostedDevice(name: name, addresses: addresses)
    }

    private func live(_ address: String, _ name: String, real: Bool = true) -> ObservedDevice {
        ObservedDevice(address: address, name: name, hasRealName: real)
    }

    private func input(_ settings: Settings,
                       _ live: [ObservedDevice],
                       kinds: [String: DeviceKind],
                       connected: Set<String>? = nil,
                       idleSeconds: Double = 0) -> BoostPolicy.Input {
        BoostPolicy.Input(settings: settings, live: live, kinds: kinds,
                          connected: connected ?? Set(live.map { $0.address.uppercased() }),
                          idleSeconds: idleSeconds, now: now)
    }

    private func row(_ decision: BoostPolicy.Decision, _ address: String) -> DeviceStatus? {
        decision.devices.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    // MARK: - Wanted

    func testAddressMatchBoostsLiveKeyboard() {
        let s = settings(boosted: [identity("K", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .keyboard]))

        XCTAssertEqual(d.actions, [.boost(address: "AA")])
        XCTAssertTrue(d.boosted)
        XCTAssertEqual(row(d, "AA")?.wanted, true)
        XCTAssertEqual(row(d, "AA")?.boosted, true)
    }

    func testDisabledReleasesEveryLiveDevice() {
        let s = settings(enabled: false, boosted: [identity("K", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .keyboard]))

        XCTAssertEqual(d.actions, [.release(address: "AA")])
        XCTAssertFalse(d.boosted)
        XCTAssertEqual(row(d, "AA")?.wanted, false)
        XCTAssertEqual(row(d, "AA")?.boosted, false)
        XCTAssertEqual(d.devices.count, 1)   // the live row, not a duplicate absent row
    }

    func testPointingDeviceIsNeverBoosted() {
        let s = settings(boosted: [identity("M", ["MOUSE"])])
        let d = BoostPolicy.decide(state(), input(s, [live("MOUSE", "M")], kinds: ["MOUSE": .pointing]))

        XCTAssertEqual(d.actions, [.release(address: "MOUSE")])
        XCTAssertEqual(row(d, "MOUSE")?.wanted, false)
        XCTAssertEqual(row(d, "MOUSE")?.kind, .pointing)
    }

    func testUnclassifiedDeviceIsNeverBoosted() {
        let s = settings(boosted: [identity("K", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .other]))

        XCTAssertEqual(d.actions, [.release(address: "AA")])
        XCTAssertEqual(row(d, "AA")?.wanted, false)
    }

    func testNameFallbackBoostsDeviceUnderNewAddress() {
        let s = settings(boosted: [identity("K", ["OLD"])])
        let d = BoostPolicy.decide(state(), input(s, [live("NEW", "K")], kinds: ["NEW": .keyboard]))

        XCTAssertEqual(d.actions, [.boost(address: "NEW")])
        XCTAssertEqual(d.learned, [live("NEW", "K")])
        XCTAssertEqual(row(d, "NEW")?.wanted, true)
    }

    func testNameFallbackIsSuppressedWhenAnAliasIsLive() {
        let s = settings(boosted: [identity("K", ["OLD"])])
        let d = BoostPolicy.decide(state(), input(s, [live("OLD", "K"), live("NEW", "K")],
                                                  kinds: ["OLD": .keyboard, "NEW": .keyboard]))

        XCTAssertTrue(d.actions.contains(.boost(address: "OLD")))
        XCTAssertTrue(d.actions.contains(.release(address: "NEW")))
        XCTAssertEqual(row(d, "OLD")?.wanted, true)
        XCTAssertEqual(row(d, "NEW")?.wanted, false)
        XCTAssertTrue(d.learned.isEmpty)
    }

    func testPlaceholderNameIsNotUsedForNameFallback() {
        let s = settings(boosted: [identity("K", ["OLD"])])
        let d = BoostPolicy.decide(state(), input(s, [live("NEW", "Device 12345", real: false)],
                                                  kinds: ["NEW": .keyboard]))

        XCTAssertEqual(d.actions, [.release(address: "NEW")])
        XCTAssertEqual(row(d, "NEW")?.wanted, false)
        XCTAssertTrue(d.learned.isEmpty)
    }

    // MARK: - Idle

    func testIdleBelowLimitKeepsBoost() {
        let s = settings(idle: 180, boosted: [identity("K", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .keyboard],
                                                  idleSeconds: 179))

        XCTAssertEqual(d.actions, [.boost(address: "AA")])
    }

    func testIdleAtLimitReleases() {
        let s = settings(idle: 180, boosted: [identity("K", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .keyboard],
                                                  idleSeconds: 180))

        XCTAssertEqual(d.actions, [.release(address: "AA")])
        XCTAssertEqual(row(d, "AA")?.wanted, true)
        XCTAssertEqual(row(d, "AA")?.boosted, false)
    }

    func testNeverReleaseIgnoresIdle() {
        let s = settings(idle: 0, boosted: [identity("K", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .keyboard],
                                                  idleSeconds: 99_999))

        XCTAssertEqual(d.actions, [.boost(address: "AA")])
    }

    // MARK: - Learning

    func testLearningFillsMissingName() {
        let s = settings(boosted: [identity("", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .keyboard]))

        XCTAssertEqual(d.learned, [live("AA", "K")])
    }

    func testLearningSkipsUnchangedIdentity() {
        let s = settings(boosted: [identity("K", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .keyboard]))

        XCTAssertTrue(d.learned.isEmpty)
    }

    func testPlaceholderNameIsNeverLearned() {
        let s = settings(boosted: [identity("", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "Device 12345", real: false)],
                                                  kinds: ["AA": .keyboard]))

        XCTAssertEqual(d.actions, [.boost(address: "AA")])
        XCTAssertTrue(d.learned.isEmpty)
    }

    // MARK: - Rows

    func testPresentDevicesSortBeforeAbsentOnes() {
        let s = settings(boosted: [identity("Absent", ["ZZ"])])
        let d = BoostPolicy.decide(state(), input(s, [live("BB", "alpha"), live("AA", "Zulu")],
                                                  kinds: ["BB": .keyboard, "AA": .keyboard,
                                                          "ZZ": .keyboard]))

        XCTAssertEqual(d.devices.map(\.address), ["BB", "AA", "ZZ"])
    }

    func testAbsentIdentityAppearsOnce() {
        let s = settings(boosted: [identity("K", ["AA", "BB"])])
        let d = BoostPolicy.decide(state(), input(s, [], kinds: ["AA": .keyboard, "BB": .keyboard]))

        XCTAssertEqual(d.devices.count, 1)
        XCTAssertEqual(d.devices[0].address, "AA")
        XCTAssertEqual(d.devices[0].present, false)
        XCTAssertEqual(d.devices[0].wanted, true)
        XCTAssertEqual(d.devices[0].boosted, false)
    }

    func testAbsentIdentityPrefersKeyboardAlias() {
        let s = settings(boosted: [identity("Combo", ["MOUSE", "KEY"])])
        let d = BoostPolicy.decide(state(), input(s, [], kinds: ["MOUSE": .pointing, "KEY": .keyboard]))

        XCTAssertEqual(d.devices.map(\.address), ["KEY"])
        XCTAssertEqual(d.devices[0].kind, .keyboard)
    }

    func testPointingOnlyIdentityIsOmitted() {
        let s = settings(boosted: [identity("M", ["MOUSE"])])
        let d = BoostPolicy.decide(state(), input(s, [], kinds: ["MOUSE": .pointing]))

        XCTAssertTrue(d.devices.isEmpty)
    }

    func testAbsentNameFallsBackToKnownNameThenAddress() {
        let s = settings(boosted: [identity("", ["AA"]), identity("", ["BB"])])
        let d = BoostPolicy.decide(state(knownNames: ["AA": "Saved"]),
                                   input(s, [], kinds: ["AA": .keyboard, "BB": .keyboard]))

        XCTAssertEqual(row(d, "AA")?.name, "Saved")
        XCTAssertEqual(row(d, "BB")?.name, "BB")
    }

    // MARK: - Boosted semantics

    func testBoostedRowNeedsAConnection() {
        let s = settings(boosted: [identity("K", ["AA"])])
        let d = BoostPolicy.decide(state(), input(s, [live("AA", "K")], kinds: ["AA": .keyboard],
                                                  connected: []))

        XCTAssertEqual(d.actions, [.boost(address: "AA")])
        XCTAssertEqual(row(d, "AA")?.boosted, false)
        XCTAssertFalse(d.boosted)
    }

    // MARK: - Sampling

    func testRSSIIsSampledEveryTenSeconds() {
        let early = BoostPolicy.decide(state(lastRSSI: now.addingTimeInterval(-9.9)),
                                       input(settings(), [], kinds: [:]))
        XCTAssertFalse(early.sampling.readRSSI)

        let due = BoostPolicy.decide(state(lastRSSI: now.addingTimeInterval(-10)),
                                     input(settings(), [], kinds: [:]))
        XCTAssertTrue(due.sampling.readRSSI)
        XCTAssertEqual(due.state.lastRSSISample, now)
    }

    func testHistoryIsRecordedEveryMinute() {
        let early = BoostPolicy.decide(state(lastHistory: now.addingTimeInterval(-59.9)),
                                       input(settings(), [], kinds: [:]))
        XCTAssertFalse(early.sampling.recordHistory)

        let due = BoostPolicy.decide(state(lastHistory: now.addingTimeInterval(-60)),
                                     input(settings(), [], kinds: [:]))
        XCTAssertTrue(due.sampling.recordHistory)
        XCTAssertEqual(due.state.lastHistoryWrite, now)
    }

    func testLossIsMeasuredOnlyAfterSettling() {
        let s = settings(boosted: [identity("K", ["AA"])])
        let snapshot = input(s, [live("AA", "K")], kinds: ["AA": .keyboard])

        let fresh = BoostPolicy.decide(state(boostedSince: now.addingTimeInterval(-69),
                                             lastHistory: now.addingTimeInterval(-60)),
                                       snapshot)
        XCTAssertTrue(fresh.sampling.recordHistory)
        XCTAssertFalse(fresh.sampling.measureLoss)

        let settled = BoostPolicy.decide(state(boostedSince: now.addingTimeInterval(-70),
                                               lastHistory: now.addingTimeInterval(-60)),
                                         snapshot)
        XCTAssertTrue(settled.sampling.recordHistory)
        XCTAssertTrue(settled.sampling.measureLoss)
    }

    func testBoostedSinceResetsWhenNothingIsBoosted() {
        let d = BoostPolicy.decide(state(boostedSince: now.addingTimeInterval(-100)),
                                   input(settings(), [], kinds: [:]))
        XCTAssertNil(d.state.boostedSince)
    }

    func testKnownNamesRecordEveryLiveDevice() {
        let d = BoostPolicy.decide(state(), input(settings(), [live("FE", "Mouse")],
                                                  kinds: ["FE": .pointing]))
        XCTAssertEqual(d.state.knownNames["FE"], "Mouse")
    }

    // MARK: - Golden

    /// The shape the installed app reports today: one keyboard and one pointing device from
    /// the same set, sharing a name. The address match must win; the name must not adopt the
    /// other half.
    func testGoldenTickMatchesInstalledStatus() {
        let keyboard = "DE:77:3F:C7:C3:32"
        let pointing = "FE:36:70:20:9F:C6"
        let name = "EWEADN V1_1"
        let s = settings(boosted: [identity(name, [keyboard])])
        let d = BoostPolicy.decide(state(), input(s,
                                                  [live(pointing, name), live(keyboard, name)],
                                                  kinds: [pointing: .pointing, keyboard: .keyboard]))

        XCTAssertTrue(d.boosted)
        XCTAssertEqual(d.devices.count, 2)

        XCTAssertEqual(row(d, keyboard)?.kind, .keyboard)
        XCTAssertEqual(row(d, keyboard)?.present, true)
        XCTAssertEqual(row(d, keyboard)?.wanted, true)
        XCTAssertEqual(row(d, keyboard)?.boosted, true)

        XCTAssertEqual(row(d, pointing)?.kind, .pointing)
        XCTAssertEqual(row(d, pointing)?.present, true)
        XCTAssertEqual(row(d, pointing)?.wanted, false)
        XCTAssertEqual(row(d, pointing)?.boosted, false)

        XCTAssertTrue(d.actions.contains(.boost(address: keyboard)))
        XCTAssertTrue(d.actions.contains(.release(address: pointing)))
        XCTAssertTrue(d.learned.isEmpty)
    }
}
