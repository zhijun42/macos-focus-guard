import Darwin
import FocusGuardKit
import Foundation

let configuration: FocusConfiguration
do {
    configuration = try FocusConfiguration.validated()
} catch {
    fputs("FocusGuard: \(error.localizedDescription)\n", stderr)
    exit(64)
}
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--check" {
    print("window \(configuration.window.label)")
    for value in arguments.dropFirst() {
        guard let minute = FocusWindow.minute(from: value) else {
            print("  \(value)  ?? unparseable")
            continue
        }
        print("  \(value)  \(configuration.window.contains(minute) ? "BLOCKED" : "allowed")")
    }
    exit(0)
}

FocusGuard(configuration: configuration).run()
