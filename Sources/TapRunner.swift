import Foundation
import CoreGraphics

protocol ScheduledTask { func cancel() }
extension Timer: ScheduledTask { func cancel() { invalidate() } }

/// Injectable clock/output let lifecycle tests run without sending real keys.
struct RunnerEnvironment {
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var hasPermission: () -> Bool = AccessibilityPermission.isGranted
    var modifiersClear: () -> Bool = {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        return CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
    }
    var schedule: (TimeInterval, @escaping () -> Void) -> ScheduledTask = { delay, action in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

final class TapRunner {
    enum Phase { case idle, countdown, running, paused, finished }
    var onUpdate: (() -> Void)?
    var canSend: () -> Bool = { false }
    private(set) var phase = Phase.idle
    private(set) var sent = 0
    private(set) var released = 0
    private(set) var pauseCount = 0
    private(set) var message = "准备好后，开始一轮敲击。"
    private(set) var settings = TapSettings()
    private var timer: ScheduledTask?
    private var keyHeld = false
    private var generation = UUID()
    private var activeStartedAt: TimeInterval?
    private var accumulatedTime: TimeInterval = 0
    private let output: KeyboardOutput
    private let environment: RunnerEnvironment

    init(output: KeyboardOutput = QuartzKeyboard(), environment: RunnerEnvironment = RunnerEnvironment()) {
        self.output = output
        self.environment = environment
    }

    var isActive: Bool { phase == .running || phase == .countdown }
    var hasSession: Bool { isActive || phase == .paused }
    var elapsed: TimeInterval {
        accumulatedTime + (activeStartedAt.map { environment.now() - $0 } ?? 0)
    }
    private var remainingTime: TimeInterval {
        settings.finishMode == .duration ? max(0, Double(settings.minutes * 60) - elapsed) : .infinity
    }

    @discardableResult func start(_ settings: TapSettings) -> Bool {
        guard !hasSession else { return false }
        if let error = settings.validationError { message = error; onUpdate?(); return false }
        guard environment.hasPermission() else {
            message = "请先开启辅助功能权限。"; onUpdate?(); return false
        }
        self.settings = settings
        sent = 0; released = 0; pauseCount = 0; accumulatedTime = 0
        generation = UUID()
        countdown(5)
        return true
    }

    func resume() {
        guard phase == .paused else { return }
        guard environment.hasPermission() else { message = "请先开启辅助功能权限。"; onUpdate?(); return }
        generation = UUID()
        countdown(3)
    }

    func pause(_ reason: String = "已暂停，点击继续可接着本轮敲击。") {
        guard isActive else { return }
        cancelPending()
        phase = .paused
        message = reason
        onUpdate?()
    }

    func stop(_ reason: String = "本轮已结束。") {
        guard hasSession else { return }
        cancelPending()
        phase = .finished
        message = reason
        onUpdate?()
    }

    func authorizationDidChange(granted: Bool) {
        if !granted { pause("已暂停：辅助功能权限已关闭。") }
        if phase == .idle {
            message = granted ? "权限已开启，点击开始即可敲击。" : "请先开启辅助功能权限。"
            onUpdate?()
        }
        // Restoring permission never resumes a paused run without user action.
    }

    private func cancelPending() {
        timer?.cancel(); timer = nil
        generation = UUID()
        releaseKey()
        if let start = activeStartedAt { accumulatedTime += environment.now() - start }
        activeStartedAt = nil
    }

    private func later(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        let expected = generation
        timer = environment.schedule(delay) { [weak self] in
            guard let self, self.isActive, self.generation == expected else { return }
            action()
        }
    }

    private func countdown(_ seconds: Int) {
        phase = .countdown
        guard canSend() else { pause("已暂停：请将 Bongo Tap 窗口置于前台。"); return }
        guard seconds > 0 else {
            activeStartedAt = environment.now()
            phase = .running
            press()
            return
        }
        message = "\(seconds) 秒后开始，请保持窗口在前台。"
        onUpdate?()
        later(1) { [weak self] in self?.countdown(seconds - 1) }
    }

    private func press() {
        guard canSend() else { pause("已暂停：切换到了其他窗口。"); return }
        guard environment.hasPermission() else { pause("已暂停：辅助功能权限不可用。"); return }
        guard environment.modifiersClear() else { pause("已暂停：请松开修饰键后继续。"); return }
        if settings.finishMode == .count && sent >= settings.count {
            stop("已达到目标次数，本轮完成。"); return
        }
        guard remainingTime > TapSettings.hold else { stop("已达到目标时长，本轮完成。"); return }
        guard output.press() else { stop("无法创建键盘事件，本轮已停止。"); return }
        let step = settings.nextStep()
        let pressedAt = environment.now()
        keyHeld = true
        sent += 1
        message = "正在敲击，A 键由本窗口接收。"
        onUpdate?()
        later(TapSettings.hold) { [weak self] in
            guard let self else { return }
            self.releaseKey()
            if self.settings.finishMode == .count && self.sent == self.settings.count {
                self.stop("已达到目标次数，本轮完成。")
                return
            }
            if step.pause > 0 {
                self.pauseCount += 1
                self.message = String(format: "随机休息 %.1f 秒…", step.pause)
            }
            self.onUpdate?()
            // Do not burst after delayed scheduling. Cap long rests at the
            // deadline; pause/resume deliberately discards the old pending rest.
            let delay = max(0.005, step.interval - (self.environment.now() - pressedAt)) + step.pause
            self.later(min(delay, self.remainingTime)) { [weak self] in self?.press() }
        }
    }

    private func releaseKey() {
        guard keyHeld else { return }
        output.release()
        keyHeld = false
        released += 1
    }
}
