import Foundation
import CoreGraphics

enum BackgroundChecks {
    static func run() {
        checkSettingsAndMatching()
        var settings = TapSettings(intervalMS: 50, jitterMS: 0, pausePercent: 0, tapMode: .background)
        let background = Harness()
        background.focused = false
        background.modifiersClear = false
        precondition(background.runner.start(settings))
        background.clock.advance(12)
        precondition(background.runner.phase == .finished && background.runner.sent == 100)
        precondition(background.runner.receipts == KeyboardReceipts(down: 100, up: 100))
        precondition(!background.keyboard.isOpen, "filter left running after completion")

        let unavailable = Harness()
        unavailable.keyboard.prepares = false
        precondition(!unavailable.runner.start(settings))
        unavailable.clock.advance(10)
        precondition(unavailable.keyboard.down == 0, "failed background setup fell back to unfiltered output")

        let delayed = Harness()
        delayed.keyboard.receiptDelay = 0.08
        settings.count = 3
        delayed.runner.start(settings)
        delayed.clock.advance(5.099)
        precondition(delayed.keyboard.down == 1, "next pair sent before previous key-up receipt")
        delayed.clock.advance(1)
        precondition(delayed.runner.phase == .finished && delayed.keyboard.down == 3 && delayed.keyboard.leaked == 0)

        let missing = Harness()
        missing.keyboard.receiptDelay = nil
        settings.count = 1
        missing.runner.start(settings)
        missing.clock.advance(10)
        precondition(missing.runner.phase == .paused && missing.keyboard.down == 1 && missing.keyboard.up == 1)
        precondition(!missing.runner.isSettling && !missing.keyboard.isOpen, "missing receipt left a live filter")
        precondition(missing.runner.receipts == KeyboardReceipts(), "missing receipt counted as delivered")
        // Permission/filter recovery does not resume; only an explicit action can.
        missing.keyboard.receiptDelay = 0
        missing.runner.authorizationDidChange(granted: true)
        missing.clock.advance(10)
        precondition(missing.keyboard.down == 1 && missing.runner.phase == .paused)

        let broken = Harness()
        settings.count = 100
        broken.keyboard.receiptDelay = 0.08
        broken.runner.start(settings)
        broken.clock.advance(5)
        broken.keyboard.healthy = false
        broken.runner.checkSafety()
        precondition(!broken.keyboard.held && broken.runner.isSettling)
        broken.clock.advance(1)
        precondition(broken.runner.phase == .paused && broken.keyboard.down == 1 && broken.keyboard.up == 1)
        precondition(!broken.keyboard.isOpen && broken.keyboard.leaked == 0)

        let stopped = Harness()
        stopped.keyboard.receiptDelay = 0.08
        stopped.runner.start(settings)
        stopped.clock.advance(5)
        stopped.runner.stop()
        precondition(stopped.runner.isSettling && stopped.keyboard.isOpen && stopped.keyboard.up == 1)
        precondition(!stopped.runner.start(settings), "new run changed tag before old key-up arrived")
        stopped.runner.resume()
        stopped.clock.advance(0.2)
        precondition(!stopped.runner.isSettling && !stopped.keyboard.isOpen && stopped.keyboard.leaked == 0)
        stopped.keyboard.receiptDelay = 0
        stopped.runner.start(settings)
        stopped.clock.advance(12)
        precondition(stopped.runner.sent == 100 && stopped.keyboard.down == 101 && stopped.keyboard.up == 101)

        let paused = Harness()
        paused.keyboard.receiptDelay = 0.08
        paused.runner.start(settings)
        paused.clock.advance(5)
        paused.runner.pause()
        paused.runner.resume()
        precondition(paused.runner.phase == .paused && paused.runner.isSettling)
        paused.clock.advance(0.2)
        paused.keyboard.receiptDelay = 0
        paused.runner.resume()
        paused.clock.advance(12)
        precondition(paused.runner.sent == 100 && paused.runner.receipts == KeyboardReceipts(down: 100, up: 100))
        precondition(paused.keyboard.leaked == 0)

        let permission = Harness()
        permission.runner.start(settings)
        permission.clock.advance(5)
        permission.permission = false
        permission.runner.checkSafety()
        permission.clock.advance(1)
        precondition(permission.runner.phase == .paused && permission.keyboard.down == 1 && permission.keyboard.up == 1)
        precondition(!permission.keyboard.isOpen)
        print("PASS: background pairing, receipt timeout, filter failure, drain/resume, settings migration and event isolation.")
    }

    private static func checkSettingsAndMatching() {
        let legacy = #"{"intervalMS":125,"jitterMS":25,"pausePercent":8,"pauseMinMS":800,"pauseMaxMS":2000,"finishMode":1,"count":234,"minutes":7}"#
        let saved = try! JSONDecoder().decode(TapSettings.self, from: Data(legacy.utf8))
        precondition(saved.tapMode == .foreground && saved.intervalMS == 125 && saved.jitterMS == 25)
        precondition(saved.pausePercent == 8 && saved.pauseMinMS == 800 && saved.pauseMaxMS == 2000)
        precondition(saved.count == 234 && saved.minutes == 7 && saved.finishMode == .duration)
        let background = TapSettings(tapMode: .background)
        let restored = try! JSONDecoder().decode(TapSettings.self, from: JSONEncoder().encode(background))
        precondition(restored.tapMode == .background)

        // Construct in-memory events only. None of these checks post real input.
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: BackgroundEventFilter.key, keyDown: down)!
            event.setIntegerValueField(.eventSourceUserData, value: 123)
            precondition(BackgroundEventFilter.matches(event, tag: 123))
            precondition(!BackgroundEventFilter.matches(event, tag: 456))
            precondition(!BackgroundEventFilter.matches(event, tag: 0))
            // Use a fresh untagged event: Quartz can cache source metadata on
            // first read, so mutating a previously read tag is not a fixture.
            let untagged = CGEvent(keyboardEventSource: nil, virtualKey: BackgroundEventFilter.key, keyDown: down)!
            precondition(!BackgroundEventFilter.matches(untagged, tag: 123), "physical F20 was matched")
            event.setIntegerValueField(.keyboardEventKeycode, value: 0)
            precondition(!BackgroundEventFilter.matches(event, tag: 123), "normal typing was matched")
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(BackgroundEventFilter.key))
            event.type = .flagsChanged
            precondition(!BackgroundEventFilter.matches(event, tag: 123), "modifier event was matched")
        }
    }
}
