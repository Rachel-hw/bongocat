import AppKit

if CommandLine.arguments.contains("--self-test") {
    RunnerChecks.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
