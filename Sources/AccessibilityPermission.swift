import ApplicationServices

enum AccessibilityPermission {
    /// The permission UI and input gate use the same accessibility trust check.
    /// Never cache a denied result across attempts or show repeated prompts.
    /// An ad-hoc rebuild can invalidate TCC's old code identity even when its
    /// settings toggle remains on. Polling cannot repair that authorization.
    static func isGranted() -> Bool { AXIsProcessTrusted() }

    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

final class PermissionMonitor {
    private let check: () -> Bool
    private(set) var granted: Bool

    init(check: @escaping () -> Bool = AccessibilityPermission.isGranted) {
        self.check = check
        granted = check()
    }

    /// Cache is only for detecting UI transitions; the runner checks live trust.
    @discardableResult func refresh() -> Bool {
        let latest = check()
        let changed = latest != granted
        granted = latest
        return changed
    }
}
