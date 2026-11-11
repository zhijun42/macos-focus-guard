import XCTest
@testable import FocusGuardKit

final class FocusGuardTests: XCTestCase {
    func testCrossMidnightWindow() {
        let window = FocusWindow(startMinute: 22 * 60 + 30, endMinute: 10 * 60 + 30)

        XCTAssertFalse(window.contains(22 * 60 + 29))
        XCTAssertTrue(window.contains(22 * 60 + 30))
        XCTAssertTrue(window.contains(10 * 60 + 29))
        XCTAssertFalse(window.contains(10 * 60 + 30))
        XCTAssertEqual(window.label, "22:30–10:30")
    }

    func testSameStartAndEndDisablesWindow() {
        let window = FocusWindow(startMinute: 600, endMinute: 600)

        XCTAssertFalse(window.contains(600))
        XCTAssertFalse(window.contains(0))
    }

    func testTimeParsingRejectsInvalidValues() {
        XCTAssertEqual(FocusWindow.minute(from: "10:30"), 630)
        XCTAssertNil(FocusWindow.minute(from: "24:00"))
        XCTAssertNil(FocusWindow.minute(from: "10:60"))
        XCTAssertNil(FocusWindow.minute(from: "1030"))
    }

    func testEnvironmentOverridesDefaults() {
        let configuration = FocusConfiguration(environment: [
            "FOCUS_START": "21:15",
            "FOCUS_END": "09:45",
            "FOCUS_APPS": "example.one, example.two",
        ])

        XCTAssertEqual(configuration.window, FocusWindow(startMinute: 1275, endMinute: 585))
        XCTAssertEqual(configuration.blockedBundleIdentifiers, ["example.one", "example.two"])
    }

    func testValidationRejectsInvalidTime() {
        XCTAssertThrowsError(try FocusConfiguration.validated(environment: [
            "FOCUS_START": "25:00",
        ])) { error in
            XCTAssertEqual(
                error as? FocusConfigurationError,
                .invalidTime(key: "FOCUS_START", value: "25:00")
            )
        }
    }

    func testValidationRejectsEmptyApplicationList() {
        XCTAssertThrowsError(try FocusConfiguration.validated(environment: [
            "FOCUS_APPS": " , ",
        ])) { error in
            XCTAssertEqual(error as? FocusConfigurationError, .emptyApplicationList)
        }
    }
}
