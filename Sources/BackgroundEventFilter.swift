import Foundation
import CoreGraphics

struct KeyboardReceipts: Equatable {
    var down = 0
    var up = 0
}

/// The game's HID observer sees each F20 before this Session filter. Consume
/// only this run's tagged F20; physical keys and other applications' events pass
/// through unchanged. The callback does no UI work, logging, or file access.
final class BackgroundEventFilter {
    static let key: CGKeyCode = 0x5A // kVK_F20
    private(set) var tag: Int64 = 0
    private(set) var receipts = KeyboardReceipts()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var failed = false
    var isHealthy: Bool { !failed && tap.map(CGEvent.tapIsEnabled) == true }

    static func matches(_ event: CGEvent, tag: Int64) -> Bool {
        tag != 0 && [.keyDown, .keyUp].contains(event.type)
            && event.getIntegerValueField(.eventSourceUserData) == tag
            && event.getIntegerValueField(.keyboardEventKeycode) == Int64(key)
    }

    func open(resetting: Bool) -> Bool {
        close()
        if resetting { receipts = KeyboardReceipts() }
        failed = false
        tag = 0x424F4E4700000000 | Int64(UInt32.random(in: 1...UInt32.max))
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<BackgroundEventFilter>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // Never silently re-enable a failed filter and keep sending.
                owner.failed = true
                return Unmanaged.passUnretained(event)
            }
            guard BackgroundEventFilter.matches(event, tag: owner.tag) else { return Unmanaged.passUnretained(event) }
            if type == .keyDown { owner.receipts.down += 1 } else { owner.receipts.up += 1 }
            return nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            close(); return false
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard isHealthy else { close(); return false }
        return true
    }

    func close() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil
    }

    deinit { close() }
}
