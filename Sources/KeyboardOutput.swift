import CoreGraphics

protocol KeyboardOutput {
    var isHealthy: Bool { get }
    var awaitingReceipt: Bool { get }
    var receipts: KeyboardReceipts? { get }
    func prepare(_ mode: TapMode, resetting: Bool) -> Bool
    func press() -> Bool
    func release()
    func close()
}

/// Create both events before posting key-down, retaining its matching key-up
/// even if the session is paused or the receiving window loses focus.
final class QuartzKeyboard: KeyboardOutput {
    static let eventTag: Int64 = 0x424F4E474F
    private var pendingRelease: CGEvent?
    private let filter = BackgroundEventFilter()
    private var mode = TapMode.foreground
    private var expected = KeyboardReceipts()
    var isHealthy: Bool { mode == .foreground || filter.isHealthy }
    var receipts: KeyboardReceipts? { mode == .background ? filter.receipts : nil }
    var awaitingReceipt: Bool { mode == .background && filter.receipts != expected }

    func prepare(_ mode: TapMode, resetting: Bool) -> Bool {
        guard pendingRelease == nil else { return false }
        filter.close()
        self.mode = mode
        guard mode == .background else { return true }
        guard filter.open(resetting: resetting) else { return false }
        // On explicit resume, a new filter starts from actual receipts. Missing
        // receipts from a failed activation remain visible, never fabricated.
        expected = filter.receipts
        return true
    }

    func press() -> Bool {
        let key: CGKeyCode = mode == .background ? BackgroundEventFilter.key : 0
        guard isHealthy, !awaitingReceipt, pendingRelease == nil,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: mode == .background ? filter.tag : Self.eventTag)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        }
        pendingRelease = up
        expected.down += 1
        down.post(tap: .cghidEventTap)
        return true
    }

    func release() {
        guard let up = pendingRelease else { return }
        expected.up += 1
        up.post(tap: .cghidEventTap)
        pendingRelease = nil
    }

    // The runner drains matching key-up before closing the Session filter.
    func close() { filter.close() }
}
