import AppKit
import Foundation

public enum GuardApplications {
    public static func running(bundleIdentifier: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
    }

    public static func running(bundleIdentifiers: Set<String>) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleIdentifier = app.bundleIdentifier else { return false }
            return !app.isTerminated && bundleIdentifiers.contains(bundleIdentifier)
        }
    }
}

public enum GuardProcess {
    @discardableResult
    public static func run(
        _ executable: String,
        arguments: [String],
        wait: Bool = false,
        discardOutput: Bool = true
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if discardOutput {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        guard wait else { return 0 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public func postUserNotification(title: String, body: String) {
    let script = """
    on run argv
        display notification (item 1 of argv) with title (item 2 of argv)
    end run
    """
    _ = try? GuardProcess.run(
        "/usr/bin/osascript",
        arguments: ["-e", script, "--", body, title]
    )
}
