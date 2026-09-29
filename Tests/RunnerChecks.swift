import Foundation

private final class FakeTask: ScheduledTask {
    let due: TimeInterval
    let action: () -> Void
    init(due: TimeInterval, action: @escaping () -> Void) { self.due = due; self.action = action }
    // Intentionally keep cancelled callbacks to exercise stale-callback guards.
    func cancel() {}
}

private final class FakeClock {
    var time: TimeInterval = 0
    var tasks: [FakeTask] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> ScheduledTask {
        let task = FakeTask(due: time + delay, action: action)
        tasks.append(task)
        return task
    }
    func advance(_ seconds: TimeInterval) {
        let target = time + seconds
        var budget = 100000
        while let index = tasks.indices.min(by: { tasks[$0].due < tasks[$1].due }), tasks[index].due <= target {
            budget -= 1
            precondition(budget > 0, "timer did not terminate")
            let task = tasks.remove(at: index)
            time = task.due
            task.action()
        }
        time = target
    }
}

private final class FakeKeyboard: KeyboardOutput {
    var down = 0
    var up = 0
    var held = false
    var succeeds = true
    func press() -> Bool {
        precondition(!held, "duplicate key-down without release")
        guard succeeds else { return false }
        down += 1; held = true
        return true
    }
    func release() {
        precondition(held, "unpaired key-up")
        up += 1; held = false
    }
}

private final class Harness {
    let clock = FakeClock()
    let keyboard = FakeKeyboard()
    var permission = true
    var focused = true
    var modifiersClear = true
    lazy var runner: TapRunner = {
        let environment = RunnerEnvironment(now: { self.clock.time }, hasPermission: { self.permission },
                                            modifiersClear: { self.modifiersClear }, schedule: { self.clock.schedule($0, $1) })
        let runner = TapRunner(output: keyboard, environment: environment)
        runner.canSend = { self.focused }
        return runner
    }()
}

enum RunnerChecks {
    static func run() {
        var allowed = false
        let permission = PermissionMonitor(check: { allowed })
        precondition(!permission.granted && !permission.refresh())
        allowed = true
        precondition(permission.refresh() && permission.granted)
        precondition(!permission.refresh())
        allowed = false
        precondition(permission.refresh() && !permission.granted)
        var settings = TapSettings()
        for _ in 0..<10000 {
            let step = settings.nextStep()
            precondition((0.050...0.150).contains(step.interval))
            precondition(step.pause == 0 || (0.5...1.5).contains(step.pause))
        }
        settings.pausePercent = 0
        let complete = Harness()
        precondition(complete.runner.start(settings))
        complete.clock.advance(4.9)
        precondition(complete.keyboard.down == 0, "countdown sent keys")
        complete.clock.advance(25)
        precondition(complete.runner.phase == .finished && complete.keyboard.down == 100 && complete.keyboard.up == 100)
        complete.clock.advance(100)
        precondition(complete.keyboard.down == 100, "events after completion")

        let pause = Harness()
        pause.runner.start(settings)
        pause.clock.advance(5)
        precondition(pause.keyboard.held)
        pause.runner.pause()
        precondition(!pause.keyboard.held && pause.keyboard.up == 1)
        pause.clock.advance(100)
        precondition(pause.keyboard.down == 1 && pause.runner.elapsed < 0.001)
        pause.runner.resume()
        pause.clock.advance(30)
        precondition(pause.runner.phase == .finished && pause.keyboard.down == 100 && pause.keyboard.up == 100)

        let cancel = Harness()
        cancel.runner.start(settings)
        cancel.clock.advance(5)
        cancel.runner.stop()
        cancel.clock.advance(30)
        precondition(cancel.keyboard.down == 1 && cancel.keyboard.up == 1)
        cancel.runner.start(settings)
        cancel.clock.advance(30)
        precondition(cancel.runner.sent == 100 && cancel.keyboard.down == 101 && cancel.keyboard.up == 101)

        let focus = Harness()
        focus.runner.start(settings)
        focus.clock.advance(5.03)
        focus.focused = false
        focus.clock.advance(1)
        precondition(focus.runner.phase == .paused && !focus.keyboard.held && focus.keyboard.down == focus.keyboard.up)

        let denied = Harness()
        denied.permission = false
        precondition(!denied.runner.start(settings))
        denied.clock.advance(10)
        precondition(denied.keyboard.down == 0)
        denied.permission = true
        denied.runner.authorizationDidChange(granted: true)
        precondition(denied.runner.phase == .idle && denied.keyboard.down == 0)
        denied.runner.start(settings)
        denied.clock.advance(5.03)
        denied.permission = false
        denied.clock.advance(1)
        precondition(denied.runner.phase == .paused && !denied.keyboard.held)
        denied.permission = true
        denied.runner.authorizationDidChange(granted: true)
        denied.clock.advance(1)
        precondition(denied.runner.phase == .paused, "permission restoration must not auto-resume")
        denied.runner.resume()
        denied.clock.advance(30)
        precondition(denied.runner.phase == .finished && denied.runner.sent == 100)

        let modified = Harness()
        modified.modifiersClear = false
        modified.runner.start(settings)
        modified.clock.advance(6)
        precondition(modified.runner.phase == .paused && modified.keyboard.down == 0)

        let timed = Harness()
        settings.finishMode = .duration
        settings.minutes = 1
        settings.pausePercent = 100
        settings.pauseMinMS = 60000; settings.pauseMaxMS = 60000
        timed.runner.start(settings)
        timed.clock.advance(66)
        precondition(timed.runner.phase == .finished && abs(timed.runner.elapsed - 60) < 0.001)
        precondition(timed.keyboard.down == 1 && timed.keyboard.up == 1)

        let failure = Harness()
        failure.keyboard.succeeds = false
        failure.runner.start(TapSettings())
        failure.clock.advance(6)
        precondition(failure.runner.phase == .finished && failure.runner.sent == 0)

        let invalid = Harness()
        settings.intervalMS = 40; settings.jitterMS = 50
        precondition(!invalid.runner.start(settings) && invalid.keyboard.down == 0)
        print("PASS: permission transitions, lifecycle checks and 10,000 timing samples; no real keys.")
    }
}
