import Foundation

enum ProbeMode: String { case foreground, background }
enum ProbePhase: String { case idle, countdown, sending, draining, finished }

protocol ProbeOutput: AnyObject {
    var receivedDown: Int { get }
    var receivedUp: Int { get }
    var healthy: Bool { get }
    func prepare(_ mode: ProbeMode) -> Bool
    func press() -> Bool
    func release()
    func close()
}

/// One bounded experiment. Every pair must be acknowledged before the next
/// pair; a missing acknowledgement never turns into an unbounded key stream.
final class ProbeSession {
    private let output: ProbeOutput
    private let now: () -> TimeInterval
    private let interval: () -> TimeInterval
    var gate: (ProbeMode) -> String? = { _ in nil }
    var onFinished: (() -> Void)?
    private(set) var phase: ProbePhase = .idle
    private(set) var mode: ProbeMode = .foreground
    private(set) var sent = 0
    private(set) var released = 0
    private(set) var message = "先验证前台 F20，再验证后台拦截。"
    private var held = false
    private var due: TimeInterval = 0
    private var releaseDue: TimeInterval = 0
    private var receiptDeadline: TimeInterval = 0
    private var drainDeadline: TimeInterval = 0
    var busy: Bool { [.countdown, .sending, .draining].contains(phase) }
    var remainingCountdown: Int { max(0, Int(ceil(due - now()))) }
    var receivedDown: Int { output.receivedDown }
    var receivedUp: Int { output.receivedUp }
    var passed: Bool {
        phase == .finished && sent == 100 && released == 100 && receivedDown == 100 && receivedUp == 100
    }

    init(output: ProbeOutput, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         interval: @escaping () -> TimeInterval = { Double.random(in: 0.05...0.15) }) {
        self.output = output; self.now = now; self.interval = interval
    }

    @discardableResult func start(_ mode: ProbeMode) -> Bool {
        guard !busy else { return false }
        if let reason = gate(mode) { message = reason; return false }
        guard output.prepare(mode) else { message = "无法准备事件接收器。请检查辅助功能权限。"; return false }
        self.mode = mode; sent = 0; released = 0; held = false
        phase = .countdown; due = now() + 8
        message = mode == .foreground ? "倒计时内读取游戏起始数字，然后不要操作键鼠。" : "倒计时内切换到输入测试窗口，再读取游戏起始数字。"
        return true
    }

    func tick() {
        let time = now()
        if phase == .draining {
            if time >= drainDeadline { complete() }
            return
        }
        guard busy else { return }
        if let reason = gate(mode) { stop(reason); return }
        guard output.healthy else { stop("接收器已失效，停止发送。"); return }
        if phase == .countdown {
            guard time >= due else { return }
            phase = .sending
        }
        if held && time >= releaseDue { releaseKey(); receiptDeadline = time + 0.3 }
        guard !held else { return }
        if receivedDown != sent || receivedUp != released {
            if time >= receiptDeadline { stop("事件确认超时，停止发送；请查看接收/拦截次数。"); }
            return
        }
        if sent == 100 { stop("已发完 100 次；工具侧通过不代表游戏计数已验证。"); return }
        guard time >= due else { return }
        guard output.press() else { stop("无法创建事件，停止发送。"); return }
        held = true; sent += 1
        releaseDue = time + 0.02
        due = time + interval()
        message = "正在发送 F20；本轮最多 100 次。"
    }

    func stop(_ reason: String = "已手动停止。") {
        guard busy && phase != .draining else { return }
        releaseKey()
        phase = .draining; drainDeadline = now() + 0.3; message = reason
    }

    private func releaseKey() {
        guard held else { return }
        output.release(); released += 1; held = false
    }

    private func complete() {
        phase = .finished
        output.close()
        onFinished?()
    }

    func shutdown() {
        releaseKey(); output.close()
    }
}
