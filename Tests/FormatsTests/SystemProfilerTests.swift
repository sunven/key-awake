import XCTest
@testable import KeyAwakeCore

final class SystemProfilerTests: XCTestCase {
    func testParsesKeyboardAndPointingDevices() {
        let text = """
              Address: 5C:9B:A6:8D:3E:6F
              Minor Type: Mouse
              Address: DE:77:3F:C7:C3:32
              Minor Type: Keyboard
        """
        XCTAssertEqual(SystemProfiler.kinds(from: text),
                       ["5C:9B:A6:8D:3E:6F": .pointing,
                        "DE:77:3F:C7:C3:32": .keyboard])
    }

    func testTrackpadAndPointingCountAsPointing() {
        let text = """
        Address: AA
        Minor Type: Trackpad
        Address: BB
        Minor Type: Pointing Device
        """
        XCTAssertEqual(SystemProfiler.kinds(from: text), ["AA": .pointing, "BB": .pointing])
    }

    func testOtherMinorTypesAreOther() {
        let text = """
        Address: AA
        Minor Type: Headset
        """
        XCTAssertEqual(SystemProfiler.kinds(from: text), ["AA": .other])
    }

    func testAddressIsUppercased() {
        let text = """
        Address: aa:bb:cc
        Minor Type: Keyboard
        """
        XCTAssertEqual(SystemProfiler.kinds(from: text), ["AA:BB:CC": .keyboard])
    }

    func testAddressWithoutMinorTypeIsDropped() {
        let text = """
        Address: AA
        Address: BB
        Minor Type: Keyboard
        """
        XCTAssertEqual(SystemProfiler.kinds(from: text), ["BB": .keyboard])
    }

    func testUnrelatedLinesAreIgnored() {
        let text = """
        Bluetooth:
          Services: 0x1812
        Address: AA
        Minor Type: Keyboard
        """
        XCTAssertEqual(SystemProfiler.kinds(from: text), ["AA": .keyboard])
    }
}
