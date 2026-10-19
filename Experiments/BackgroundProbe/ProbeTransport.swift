import AppKit
import CoreGraphics

final class ProbeTransport: ProbeOutput {
    static let key: CGKeyCode = 0x5A // kVK_F20, not a Unicode character code.
    private(set) var tag: Int64 = 0
    private(set) var receivedDown = 0
    private(set) var receivedUp = 0
    private var mode: ProbeMode = .foreground
    private var tap: CFMachPort?
    private var runSource: CFRunLoopSource?
    private var pendingUp: CGEvent?
    private var failed = false
    var healthy: Bool { !failed && (mode == .foreground || tap.map(CGEvent.tapIsEnabled) == true) }

    static func matches(_ event: CGEvent, tag: Int64) -> Bool {
        tag != 0 && [.keyDown, .keyUp].contains(event.type)
            && event.getIntegerValueField(.eventSourceUserData) == tag
            && event.getIntegerValueField(.keyboardEventKeycode) == Int64(key)
    }

    func prepare(_ mode: ProbeMode) -> Bool {
        close()
        self.mode = mode; failed = false; receivedDown = 0; receivedUp = 0
        tag = 0x424F4E4700000000 | Int64(UInt32.random(in: 1...UInt32.max))
        guard mode == .background else { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        // The game's HID observer runs before this session filter. Only our
        // per-run tag AND F20 are consumed; all physical input is passed on.
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<ProbeTransport>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                owner.failed = true
                return Unmanaged.passUnretained(event)
            }
            if owner.consume(event) { return nil }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { close(); return false }
        runSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return healthy
    }

    private func consume(_ event: CGEvent) -> Bool {
        guard Self.matches(event, tag: tag) else { return false }
        if event.type == .keyDown { receivedDown += 1 } else { receivedUp += 1 }
        return true
    }

    func receiveLocal(_ event: NSEvent) -> NSEvent? {
        guard let cg = event.cgEvent, Self.matches(cg, tag: tag) else { return event }
        if mode == .foreground { _ = consume(cg) }
        // Background delivery here means the filter leaked; do not credit it.
        return nil
    }

    func press() -> Bool {
        guard healthy, pendingUp == nil,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: Self.key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: Self.key, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: tag)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        }
        pendingUp = up
        down.post(tap: .cghidEventTap)
        return true
    }

    func release() { pendingUp?.post(tap: .cghidEventTap); pendingUp = nil }

    func close() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; runSource = nil
    }

    deinit { close() }
}
