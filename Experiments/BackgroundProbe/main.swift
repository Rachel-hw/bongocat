import AppKit

if CommandLine.arguments.contains("--self-test") {
    ProbeChecks.run()
} else {
    let app = NSApplication.shared
    let delegate: NSApplicationDelegate = Bundle.main.object(forInfoDictionaryKey: "ProbeRole") as? String == "receiver"
        ? ReceiverDelegate() : LabDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
