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
    private(set) var isSettling = false
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
    var hasSession: Bool { isActive || phase == .paused || isSettling }
    var receipts: KeyboardReceipts? { output.receipts }
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
        guard output.prepare(settings.tapMode, resetting: true) else {
            message = "无法启动后台模式，请检查辅助功能权限后重试。"; onUpdate?(); return false
        }
        self.settings = settings
        sent = 0; released = 0; pauseCount = 0; accumulatedTime = 0
        generation = UUID()
        countdown(5)
        return true
    }

    func resume() {
        guard phase == .paused, !isSettling else { return }
        guard environment.hasPermission() else { message = "请先开启辅助功能权限。"; onUpdate?(); return }
        guard output.prepare(settings.tapMode, resetting: false) else {
            message = "无法恢复后台模式，请检查辅助功能权限后重试。"; onUpdate?(); return
        }
        generation = UUID()
        countdown(3)
    }

    func pause(_ reason: String = "已暂停，点击继续可接着本轮敲击。") {
        guard isActive else { return }
        cancelPending()
        phase = .paused
        message = reason
        drainOutput(until: environment.now() + 0.3)
    }

    func stop(_ reason: String = "本轮已结束。") {
        guard hasSession else { return }
        if isSettling {
            phase = .finished; message = reason; onUpdate?(); return
        }
        cancelPending()
        phase = .finished
        message = reason
        drainOutput(until: environment.now() + 0.3)
    }

    func authorizationDidChange(granted: Bool) {
        if !granted { pause("已暂停：辅助功能权限已关闭。") }
        if phase == .idle {
            message = granted ? "权限已开启，点击开始即可敲击。" : "请先开启辅助功能权限。"
            onUpdate?()
        }
        // Restoring permission never resumes a paused run without user action.
    }

    /// Also checked by the UI heartbeat, including during long random rests.
    func checkSafety() {
        guard isActive else { return }
        if !environment.hasPermission() { pause("已暂停：辅助功能权限不可用。") }
        else if !output.isHealthy { pause("已暂停：后台接收器已失效，请检查权限后继续。") }
        else if settings.tapMode == .foreground && !canSend() { pause("已暂停：请将 Bongo Tap 窗口置于前台。") }
    }

    /// Keep the filter alive until the last matching key-up arrives. Block new
    /// sessions/resumes during this bounded drain so tags cannot change early.
    private func drainOutput(until deadline: TimeInterval) {
        isSettling = output.awaitingReceipt
        if !isSettling || environment.now() >= deadline {
            if isSettling { message = "后台事件未完整确认，已停止发送；请检查权限后再试。" }
            output.close()
            isSettling = false
            onUpdate?()
            return
        }
        onUpdate?()
        let expected = generation
        timer = environment.schedule(0.01) { [weak self] in
            guard let self, self.generation == expected else { return }
            self.drainOutput(until: deadline)
        }
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
        checkSafety()
        guard isActive else { return }
        guard seconds > 0 else {
            activeStartedAt = environment.now()
            phase = .running
            press()
            return
        }
        message = settings.tapMode == .background
            ? "\(seconds) 秒后开始，可以切换到其他应用。"
            : "\(seconds) 秒后开始，请保持窗口在前台。"
        onUpdate?()
        later(1) { [weak self] in self?.countdown(seconds - 1) }
    }

    private func press() {
        checkSafety()
        guard isActive else { return }
        // Background F20 is filtered before foreground shortcut handling, so
        // normal Shift/Command typing must not pause a background session.
        if settings.tapMode == .foreground && !environment.modifiersClear() {
            pause("已暂停：请松开修饰键后继续。"); return
        }
        if settings.finishMode == .count && sent >= settings.count {
            stop("已达到目标次数，本轮完成。"); return
        }
        guard remainingTime > TapSettings.hold else { stop("已达到目标时长，本轮完成。"); return }
        guard output.press() else { stop("无法创建键盘事件，本轮已停止。"); return }
        let step = settings.nextStep()
        let pressedAt = environment.now()
        keyHeld = true
        sent += 1
        message = settings.tapMode == .background ? "正在后台敲击，可以正常使用其他应用。" : "正在敲击，A 键由本窗口接收。"
        onUpdate?()
        later(TapSettings.hold) { [weak self] in
            guard let self else { return }
            self.releaseKey()
            self.afterRelease(step: step, pressedAt: pressedAt, deadline: self.environment.now() + 0.3)
        }
    }

    private func afterRelease(step: (interval: TimeInterval, pause: TimeInterval),
                              pressedAt: TimeInterval, deadline: TimeInterval) {
        checkSafety()
        guard isActive else { return }
        if output.awaitingReceipt {
            guard environment.now() < deadline else { pause("已暂停：后台事件确认超时。"); return }
            later(0.01) { [weak self] in self?.afterRelease(step: step, pressedAt: pressedAt, deadline: deadline) }
            return
        }
        if settings.finishMode == .count && sent == settings.count {
            stop("已达到目标次数，本轮完成。")
            return
        }
        if step.pause > 0 {
            pauseCount += 1
            message = String(format: "随机休息 %.1f 秒…", step.pause)
        }
        onUpdate?()
        // Never catch up in bursts after delayed acknowledgement or scheduling.
        // Long rests end at the duration deadline; resume discards the old rest.
        let delay = max(0.005, step.interval - (environment.now() - pressedAt)) + step.pause
        later(min(delay, remainingTime)) { [weak self] in self?.press() }
    }

    private func releaseKey() {
        guard keyHeld else { return }
        output.release()
        keyHeld = false
        released += 1
    }
}
