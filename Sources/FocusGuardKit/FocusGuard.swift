import AppKit
import Foundation
import GuardCore

public enum FocusConfigurationError: LocalizedError, Equatable {
    case invalidTime(key: String, value: String)
    case emptyApplicationList

    public var errorDescription: String? {
        switch self {
        case .invalidTime(let key, let value):
            return "\(key) 必须是有效的 HH:MM 时间，收到：\(value)"
        case .emptyApplicationList:
            return "FOCUS_APPS 必须包含至少一个 bundle identifier。"
        }
    }
}

public struct FocusWindow: Equatable {
    public let startMinute: Int
    public let endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public func contains(_ minute: Int) -> Bool {
        if startMinute == endMinute { return false }
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }

    public var label: String {
        func format(_ minute: Int) -> String {
            String(format: "%02d:%02d", minute / 60, minute % 60)
        }
        return "\(format(startMinute))–\(format(endMinute))"
    }

    public static func minute(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }
}

public struct FocusConfiguration: Equatable {
    public let window: FocusWindow
    public let blockedBundleIdentifiers: Set<String>
    public let pollInterval: TimeInterval
    public let forceTerminationDelay: TimeInterval
    public let notificationCooldown: TimeInterval
    public let debugEnabled: Bool

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        pollInterval: TimeInterval = 2,
        forceTerminationDelay: TimeInterval = 4,
        notificationCooldown: TimeInterval = 30
    ) {
        let start = environment["FOCUS_START"].flatMap(FocusWindow.minute(from:)) ?? 22 * 60 + 30
        let end = environment["FOCUS_END"].flatMap(FocusWindow.minute(from:)) ?? 10 * 60 + 30
        let defaults = [
            "com.tencent.xinWeChat",
            "com.operasoftware.Opera",
            "com.zhijun.opera-guard",
            "com.apple.Photos",
        ]
        let configured = environment["FOCUS_APPS"]
            .map { value in
                value.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        self.window = FocusWindow(startMinute: start, endMinute: end)
        self.blockedBundleIdentifiers = Set(configured ?? defaults)
        self.pollInterval = pollInterval
        self.forceTerminationDelay = forceTerminationDelay
        self.notificationCooldown = notificationCooldown
        self.debugEnabled = environment["FOCUS_DEBUG"] != nil
    }

    public static func validated(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> FocusConfiguration {
        for key in ["FOCUS_START", "FOCUS_END"] {
            if let value = environment[key], FocusWindow.minute(from: value) == nil {
                throw FocusConfigurationError.invalidTime(key: key, value: value)
            }
        }
        if let value = environment["FOCUS_APPS"] {
            let applications = value.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if applications.isEmpty {
                throw FocusConfigurationError.emptyApplicationList
            }
        }
        return FocusConfiguration(environment: environment)
    }
}

public final class FocusGuard {
    private let configuration: FocusConfiguration
    private var lastNotification: [String: Date] = [:]
    private var pendingForceTermination: Set<pid_t> = []
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    public init(configuration: FocusConfiguration = FocusConfiguration()) {
        self.configuration = configuration
    }

    public func sweep(at date: Date = Date()) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard configuration.window.contains(minute) else { return }
        for application in GuardApplications.running(
            bundleIdentifiers: configuration.blockedBundleIdentifiers
        ) {
            close(application)
        }
    }

    public func run() -> Never {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sweep()
        })
        timer = Timer.scheduledTimer(
            withTimeInterval: configuration.pollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sweep()
        }
        debug("started; window \(configuration.window.label); watching \(configuration.blockedBundleIdentifiers.sorted().joined(separator: ", "))")
        sweep()
        RunLoop.main.run()
        fatalError("RunLoop.main unexpectedly returned")
    }

    private func close(_ application: NSRunningApplication) {
        guard let identifier = application.bundleIdentifier else { return }
        let name = application.localizedName ?? identifier
        debug("in window, closing \(name) (pid \(application.processIdentifier))")
        notify(name: name, identifier: identifier)
        application.terminate()

        let pid = application.processIdentifier
        guard !pendingForceTermination.contains(pid) else { return }
        pendingForceTermination.insert(pid)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + configuration.forceTerminationDelay
        ) { [weak self] in
            self?.pendingForceTermination.remove(pid)
            guard let running = NSRunningApplication(processIdentifier: pid),
                  !running.isTerminated else {
                return
            }
            self?.debug("\(name) ignored the quit request, forcing")
            running.forceTerminate()
        }
    }

    private func notify(name: String, identifier: String) {
        if let last = lastNotification[identifier],
           Date().timeIntervalSince(last) < configuration.notificationCooldown {
            return
        }
        lastNotification[identifier] = Date()
        postUserNotification(
            title: "专注时间 \(configuration.window.label)",
            body: "\(name) 已关闭"
        )
    }

    private func debug(_ message: String) {
        guard configuration.debugEnabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[focus \(timestamp)] \(message)\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
    }
}
