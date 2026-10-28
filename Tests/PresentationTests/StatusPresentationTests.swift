import XCTest
@testable import KeyAwakeCore

final class StatusPresentationTests: XCTestCase {
    private func settings(enabled: Bool = true) -> Settings {
        var value = Settings()
        value.enabled = enabled
        return value
    }

    private func status(active: Bool = false, bluetooth: BluetoothState = .on,
                        apiAvailable: Bool = true) -> AgentStatus {
        AgentStatus(bluetooth: bluetooth, active: active, apiAvailable: apiAvailable,
                    devices: [], rssi: nil, lossPercent: nil,
                    radioCyclesLastHour: 0, updated: .init())
    }

    private func describe(_ settings: Settings, _ status: AgentStatus,
                          _ liveness: StatusPresentation.EngineLiveness = .alive)
        -> StatusPresentation.Presentation {
        StatusPresentation.describe(settings: settings, status: status, liveness: liveness)
    }

    private func device(present: Bool = true, kind: DeviceKind = .keyboard,
                        wanted: Bool = true, boosted: Bool = false) -> DeviceStatus {
        DeviceStatus(address: "AA", name: "K", kind: kind, present: present,
                     wanted: wanted, boosted: boosted)
    }

    // MARK: - Precedence

    func testDisabledWinsAndTheMenuStillIgnoresProblems() {
        let p = describe(settings(enabled: false), status(active: true, bluetooth: .off))

        XCTAssertEqual(p.state, .disabled)
        XCTAssertEqual(p.problem, L("Bluetooth is turned off."))
        XCTAssertEqual(p.tone, .neutral)
        XCTAssertEqual(p.symbol, "bolt.slash")
        XCTAssertEqual(p.shortHeadline, L("Disabled"))
        XCTAssertEqual(p.menuHeadline, L("KeyAwake — disabled"))
    }

    func testDisabledWithTheEngineAbsentKeepsTheWarning() {
        let p = describe(settings(enabled: false), status(active: true),
                         .absent(launchAtLogin: false))

        XCTAssertEqual(p.state, .disabled)
        XCTAssertEqual(p.problem, L("The engine is not running. Reopen KeyAwake to start it."))
        XCTAssertEqual(p.menuHeadline, L("KeyAwake — disabled"))
    }

    func testEngineAbsentUsesTheLaunchAtLoginWording() {
        let responding = describe(settings(), status(active: true), .absent(launchAtLogin: true))
        XCTAssertEqual(responding.state, .stopped)
        XCTAssertEqual(responding.problem,
                       L("The engine is not responding. Try turning “Start at login” off and on again."))
        XCTAssertEqual(responding.shortHeadline, L("Stopped"))
        XCTAssertEqual(responding.menuHeadline, responding.problem)

        let notRunning = describe(settings(), status(), .absent(launchAtLogin: false))
        XCTAssertEqual(notRunning.problem,
                       L("The engine is not running. Reopen KeyAwake to start it."))
    }

    func testEngineAbsentBeatsBluetooth() {
        let p = describe(settings(), status(bluetooth: .off), .absent(launchAtLogin: false))
        XCTAssertEqual(p.problem, L("The engine is not running. Reopen KeyAwake to start it."))
    }

    func testBluetoothBeatsAPIAvailability() {
        let p = describe(settings(), status(active: true, bluetooth: .off, apiAvailable: false))
        XCTAssertEqual(p.problem, L("Bluetooth is turned off."))
        XCTAssertEqual(p.state, .stopped)
    }

    func testAPIAvailabilityStopsActivity() {
        let p = describe(settings(), status(active: true, apiAvailable: false))

        XCTAssertEqual(p.state, .stopped)
        XCTAssertEqual(p.problem,
                       L("This version of macOS no longer exposes the latency setting. KeyAwake cannot help."))
        XCTAssertEqual(p.tone, .neutral)
        XCTAssertEqual(p.symbol, "bolt.slash")
    }

    func testBoosting() {
        let p = describe(settings(), status(active: true))

        XCTAssertEqual(p.state, .boosting)
        XCTAssertNil(p.problem)
        XCTAssertEqual(p.tone, .positive)
        XCTAssertEqual(p.symbol, "bolt.fill")
        XCTAssertEqual(p.shortHeadline, L("Boosting"))
        XCTAssertEqual(p.menuHeadline, L("KeyAwake — boosting"))
    }

    func testIdle() {
        let p = describe(settings(), status(active: false))

        XCTAssertEqual(p.state, .idle)
        XCTAssertNil(p.problem)
        XCTAssertEqual(p.tone, .attention)
        XCTAssertEqual(p.symbol, "bolt")
        XCTAssertEqual(p.shortHeadline, L("Idle"))
        XCTAssertEqual(p.menuHeadline, L("KeyAwake — idle"))
    }

    // MARK: - Device detail

    func testDeviceDetail() {
        XCTAssertEqual(StatusPresentation.detail(for: device(present: false), enabled: true),
                       L("away"))
        XCTAssertEqual(StatusPresentation.detail(for: device(kind: .pointing), enabled: true),
                       L("not supported"))
        XCTAssertEqual(StatusPresentation.detail(for: device(wanted: false), enabled: true), "—")
        XCTAssertEqual(StatusPresentation.detail(for: device(), enabled: false), L("off"))
        XCTAssertEqual(StatusPresentation.detail(for: device(boosted: true), enabled: true),
                       L("latency 0"))
        XCTAssertEqual(StatusPresentation.detail(for: device(), enabled: true), L("idle"))
    }
}
