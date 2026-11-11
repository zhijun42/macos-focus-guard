import Darwin
import Foundation
import OperaGuardKit

let support = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/The Opera", isDirectory: true)
let guardApp = OperaGuard(
    bundleID: "com.operasoftware.Opera",
    bundleURL: URL(fileURLWithPath: "/Applications/Opera.app"),
    store: StateStore(directory: support)
)

do {
    switch Array(CommandLine.arguments.dropFirst()) {
    case ["monitor"]:
        guardApp.monitor()
    case ["status"]:
        print(try guardApp.check().joined(separator: "\n"))
    case let arguments where arguments.count == 2 && arguments[0] == "start":
        print(try guardApp.check(minutes: arguments[1]).joined(separator: "\n"))
    default:
        throw NSError(
            domain: "The Opera",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "无效的启动命令。"]
        )
    }
} catch {
    fputs("The Opera: \(error.localizedDescription)\n", stderr)
    exit(1)
}
