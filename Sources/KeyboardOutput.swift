import CoreGraphics

protocol KeyboardOutput {
    func press() -> Bool
    func release()
}

/// Create both events before posting key-down, retaining its matching key-up
/// even if the session is paused or the receiving window loses focus.
final class QuartzKeyboard: KeyboardOutput {
    static let eventTag: Int64 = 0x424F4E474F
    private var pendingRelease: CGEvent?

    func press() -> Bool {
        guard pendingRelease == nil,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        }
        pendingRelease = up
        down.post(tap: .cghidEventTap)
        return true
    }

    func release() {
        pendingRelease?.post(tap: .cghidEventTap)
        pendingRelease = nil
    }
}
