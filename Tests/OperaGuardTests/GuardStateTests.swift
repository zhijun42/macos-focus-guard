import XCTest
@testable import OperaGuardKit

final class GuardStateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return calendar
    }

    func testCrossMidnightUsageAndCooldown() throws {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6))!
        let now = midnight.addingTimeInterval(60)
        let browser = BrowserProcess(pid: 1234, launchedAt: midnight.addingTimeInterval(-600))
        var state = GuardState(trackingStartedAt: browser.launchedAt)
        state.active = ViewingSession(
            browser: browser,
            startedAt: browser.launchedAt,
            deadline: now,
            lastSeenAt: now,
            stopping: true
        )

        XCTAssertEqual(state.usage(on: now, calendar: calendar).seconds, 60)
        XCTAssertEqual(state.usage(on: now, calendar: calendar).opens, 0)
        XCTAssertTrue(state.recordExit(at: now, observed: true))
        XCTAssertEqual(state.unlockAt, now.addingTimeInterval(GuardState.cooldown))
        XCTAssertEqual(state.usage(on: midnight.addingTimeInterval(-1), calendar: calendar).opens, 1)
    }

    func testRestartUsesLastObservedTime() {
        let now = Date()
        let browser = BrowserProcess(pid: 1234, launchedAt: now)
        var state = GuardState(
            active: ViewingSession(
                browser: browser,
                startedAt: now,
                deadline: now.addingTimeInterval(1200),
                lastSeenAt: now.addingTimeInterval(120)
            )
        )

        XCTAssertFalse(state.recordExit(at: now.addingTimeInterval(3600), observed: false))
        XCTAssertEqual(state.unlockAt, now.addingTimeInterval(120 + GuardState.cooldown))
    }
}
