import AppKit
import Darwin
import Foundation

struct BrowserProcess: Codable, Equatable {
    var pid: pid_t
    var launchedAt: Date

    init?(_ app: NSRunningApplication) {
        guard let launchedAt = app.launchDate else { return nil }
        self.init(pid: app.processIdentifier, launchedAt: launchedAt)
    }

    init(pid: pid_t, launchedAt: Date) {
        self.pid = pid
        self.launchedAt = launchedAt
    }
}

struct ViewingSession: Codable, Equatable {
    var browser: BrowserProcess
    var startedAt: Date
    var deadline: Date
    var lastSeenAt: Date
    var warned = false
    var stopping = false
}

struct CompletedSession: Codable, Equatable {
    var startedAt: Date
    var endedAt: Date
}

struct GuardState: Codable, Equatable {
    static let cooldown: TimeInterval = 30 * 60

    var trackingStartedAt = Date()
    var active: ViewingSession?
    var completed: [CompletedSession] = []

    var unlockAt: Date? {
        completed.last?.endedAt.addingTimeInterval(Self.cooldown)
    }

    mutating func recordExit(at now: Date, observed: Bool) -> Bool {
        guard let session = active else { return false }
        // A missing process after a restart may have quit long before this check.
        let recentlySeen = now.timeIntervalSince(session.lastSeenAt) <= 10
        let endedAt = max(session.startedAt, observed || recentlySeen ? now : session.lastSeenAt)
        completed.append(CompletedSession(startedAt: session.startedAt, endedAt: endedAt))
        active = nil
        return session.stopping && now.timeIntervalSince(endedAt) <= 10
    }

    func usage(on now: Date, calendar: Calendar = .autoupdatingCurrent) -> (seconds: Int, opens: Int) {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return (0, 0) }
        var elapsed: TimeInterval = 0
        var opens = 0
        func count(_ start: Date, _ end: Date) {
            if start >= day.start && start < day.end { opens += 1 }
            elapsed += max(0, min(end, now, day.end).timeIntervalSince(max(start, day.start)))
        }
        for session in completed {
            count(session.startedAt, session.endedAt)
        }
        if let active {
            count(active.startedAt, now)
        }
        return (Int(elapsed), opens)
    }

    func summary(at now: Date) -> String {
        let today = usage(on: now)
        let hours = today.seconds / 3600
        let minutes = today.seconds / 60 % 60
        let duration: String
        if hours > 0 {
            duration = "\(hours) 小时 \(minutes) 分钟"
        } else if minutes > 0 || today.seconds == 0 {
            duration = "\(minutes) 分钟"
        } else {
            duration = "\(today.seconds) 秒"
        }
        let sinceUpdate = Calendar.autoupdatingCurrent.isDate(trackingStartedAt, inSameDayAs: now)
            ? "（自更新起）" : ""
        return "今天已用 \(duration)  ·  已开 \(today.opens) 轮\(sinceUpdate)"
    }
}

struct StateStore {
    let directory: URL

    func update<Result>(_ operation: (inout GuardState) throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let lockPath = directory.appendingPathComponent("state.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }

        let stateURL = directory.appendingPathComponent("state.json")
        let original: GuardState?
        do {
            original = try JSONDecoder().decode(GuardState.self, from: Data(contentsOf: stateURL))
        } catch CocoaError.fileReadNoSuchFile {
            original = nil
        }
        var state = original ?? GuardState()
        let result = try operation(&state)
        if state != original {
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        }
        return result
    }
}

struct OperaGuard {
    let bundleID: String
    let bundleURL: URL
    let store: StateStore

    private enum Effect {
        case warning(minutes: Int)
        case displaySleep
    }

    private func browsers() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
    }

    private func run(_ path: String, _ arguments: [String], wait: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if !wait {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        if wait {
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "The Opera", code: Int(process.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: "系统未能打开 Opera。"])
            }
        }
    }

    private func reconcile(_ state: inout GuardState, at now: Date, exitedPID: pid_t?) -> Effect? {
        let apps = browsers()
        var effect: Effect?
        if var session = state.active {
            let observedExit = exitedPID == session.browser.pid
            if let app = apps.first(where: { BrowserProcess($0) == session.browser }), !observedExit {
                let remaining = session.deadline.timeIntervalSince(now)
                if remaining <= 0 {
                    session.stopping = true
                    app.forceTerminate()
                } else if !session.warned, remaining <= 600,
                          session.deadline.timeIntervalSince(session.startedAt) > 600 {
                    session.warned = true
                    effect = .warning(minutes: Int(ceil(remaining / 60)))
                }
                if now.timeIntervalSince(session.lastSeenAt) >= 5 {
                    session.lastSeenAt = now
                }
                state.active = session
            } else if state.recordExit(at: now, observed: observedExit) {
                effect = .displaySleep
            }
        }
        for app in apps where state.active?.browser.pid != app.processIdentifier {
            app.forceTerminate()
        }
        return effect
    }

    private func status(_ state: GuardState, at now: Date) -> [String] {
        let summary = state.summary(at: now)
        if let session = state.active {
            let remaining = max(0, Int(ceil(session.deadline.timeIntervalSince(now) / 60)))
            let detail = session.stopping ? "观看时间已到，正在关闭 Opera。" : "本轮还剩 \(remaining) 分钟。"
            return ["watching", summary, detail]
        }
        if let unlockAt = state.unlockAt, unlockAt > now {
            let time = DateFormatter.localizedString(from: unlockAt, dateStyle: .none, timeStyle: .medium)
            return ["cooldown", summary, "休息时间。最早 \(time) 可以再开。"]
        }
        return ["ready", summary, "这次打算看多久？请输入分钟数，时间一到 Opera 会关闭。"]
    }

    private func openBrowser() throws -> BrowserProcess {
        try run("/usr/bin/open", ["-a", bundleURL.path], wait: true)
        let waitUntil = ProcessInfo.processInfo.systemUptime + 8
        repeat {
            if let browser = browsers().compactMap(BrowserProcess.init).first {
                return browser
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while ProcessInfo.processInfo.systemUptime < waitUntil
        throw NSError(domain: "The Opera", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "未能确认 Opera 已打开，请重试。"])
    }

    func check(minutes input: String? = nil, exitedPID: pid_t? = nil) throws -> [String] {
        let (response, effect) = try store.update { state -> ([String], Effect?) in
            let now = Date()
            let effect = reconcile(&state, at: now, exitedPID: exitedPID)
            let current = status(state, at: now)
            guard let input, current[0] == "ready" else { return (current, effect) }
            guard let minutes = Int(input), minutes > 0, minutes <= Int(Int32.max) / 60,
                  String(minutes) == input else {
                return (["invalid", current[1], "请输入一个正整数（分钟）。"], effect)
            }
            // A previously unapproved Opera process must finish exiting before a new launch.
            guard browsers().isEmpty else {
                return (["retry", current[1], "正在关闭原来的 Opera，请稍后再试。"], effect)
            }
            let browser = try openBrowser()
            let startedAt = browser.launchedAt
            state.active = ViewingSession(browser: browser, startedAt: startedAt,
                                          deadline: startedAt.addingTimeInterval(Double(minutes) * 60),
                                          lastSeenAt: startedAt)
            return (["started"], effect)
        }
        switch effect {
        case .warning(let minutes):
            notify("本轮还剩 \(minutes) 分钟，可以开始收尾了。")
        case .displaySleep:
            notify("时间到，Opera 已关闭。")
            try? run("/usr/bin/pmset", ["displaysleepnow"])
        case nil:
            break
        }
        return response
    }

    private func notify(_ message: String) {
        try? run("/usr/bin/osascript",
                 ["-e", "display notification \"\(message)\" with title \"Opera 观看守卫\""])
    }

    func monitor() {
        @Sendable func checkBrowser(exitedPID: pid_t? = nil) {
            do { _ = try check(exitedPID: exitedPID) }
            catch { fputs("The Opera: \(error.localizedDescription)\n", stderr) }
        }
        let center = NSWorkspace.shared.notificationCenter
        let launch = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                        object: nil, queue: .main) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == bundleID { checkBrowser() }
        }
        let exit = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                      object: nil, queue: .main) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == bundleID { checkBrowser(exitedPID: app?.processIdentifier) }
        }
        defer {
            center.removeObserver(launch)
            center.removeObserver(exit)
        }
        checkBrowser()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in checkBrowser() }
        defer { timer.invalidate() }
        RunLoop.main.run()
    }
}
