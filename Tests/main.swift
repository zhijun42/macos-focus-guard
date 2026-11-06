import AppKit
import Foundation

func require(_ passes: Bool, _ description: String) throws {
    guard passes else {
        throw NSError(domain: "OperaGuardTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: description])
    }
    print("PASS: \(description)")
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let support = root.appendingPathComponent("fixture-state")
let store = StateStore(directory: support)
let identifier = CommandLine.arguments[2]
let fixtureURL = root.appendingPathComponent("Opera Guard Fixture.app")
let guardApp = OperaGuard(bundleID: identifier, bundleURL: fixtureURL, store: store)

if CommandLine.arguments.dropFirst().contains("monitor") {
    guardApp.monitor()
    exit(0)
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6))!
let now = midnight.addingTimeInterval(60)
let browser = BrowserProcess(pid: 1234, launchedAt: midnight.addingTimeInterval(-600))
var history = GuardState(trackingStartedAt: browser.launchedAt)
history.active = ViewingSession(browser: browser, startedAt: browser.launchedAt,
                                deadline: now, lastSeenAt: now, stopping: true)
try require(history.usage(on: now, calendar: calendar) == (60, 0), "cross-midnight usage")
try require(history.recordExit(at: now, observed: true), "timeout exit signals display sleep")
try require(history.unlockAt == now.addingTimeInterval(1800), "timeout exit sets 30-minute cooldown")
try require(history.usage(on: now, calendar: calendar) == (60, 0), "ended cross-midnight session")
try require(history.usage(on: midnight.addingTimeInterval(-1), calendar: calendar) == (599, 1),
            "opening is attributed to the day it started")
history.active = ViewingSession(browser: browser, startedAt: now, deadline: now.addingTimeInterval(1200),
                                lastSeenAt: now.addingTimeInterval(120))
try require(!history.recordExit(at: now.addingTimeInterval(3600), observed: false),
            "recovering after a restart does not trigger display sleep")
try require(history.unlockAt == now.addingTimeInterval(1920), "restart uses last observed browser time")

func runIntegration() throws {
    let monitor = Process()
    monitor.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    monitor.arguments = [root.path, identifier, "monitor"]
    try monitor.run()
    defer {
        if monitor.isRunning { monitor.terminate() }
        monitor.waitUntilExit()
        for fixture in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
            fixture.forceTerminate()
        }
    }

    try require(guardApp.check()[0] == "ready", "empty state can start")
    try require(guardApp.check(minutes: "0")[0] == "invalid", "invalid duration is rejected")
    try require(guardApp.check(minutes: "40")[0] == "started", "launches a real fixture application")
    let original = try store.update { $0.active }
    try require(original != nil, "successful start records an active session")
    try require(guardApp.check(minutes: "60")[0] == "watching", "repeated start reports active session")
    let repeated = try store.update { $0.active }
    try require(original?.deadline == repeated?.deadline, "repeated start keeps the original deadline")

    let fixture = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
    try require(fixture?.terminate() == true, "requested an independent browser quit")
    let waitUntil = Date().addingTimeInterval(10)
    while Date() < waitUntil {
        let active = try store.update { $0.active != nil }
        print("Quit observation: fixture session is \(active ? "active" : "closed")")
        if !active { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    let ended = try store.update { $0.completed.last }
    try require(ended != nil, "monitor records an independent browser quit")
    try require(guardApp.check(minutes: "40")[0] == "cooldown", "manual exit blocks immediate relaunch")
    let result = try store.update { $0 }
    try require(result.usage(on: Date()).opens == 1, "only one successful open is counted")
    try require(result.unlockAt == ended?.endedAt.addingTimeInterval(1800), "retry preserves unlock time")

    let direct = Process()
    direct.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    direct.arguments = ["-a", fixtureURL.path]
    try direct.run()
    direct.waitUntilExit()
    try require(direct.terminationStatus == 0, "direct launch requested")
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    try require(NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty,
                "monitor closes direct launches during cooldown")
    try require(store.update { $0.usage(on: Date()).opens } == 1, "direct attempt does not add a session")
}

do {
    try runIntegration()
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}
