import AppKit

func probeReport(_ name: String, _ data: [String: Any]) {
    guard let directory = Bundle.main.object(forInfoDictionaryKey: "ProbeResultDirectory") as? String else { return }
    let folder = URL(fileURLWithPath: directory)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? json.write(to: folder.appendingPathComponent(name + ".json"), options: .atomic)
}

final class LabDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let output = ProbeTransport()
    private lazy var session = ProbeSession(output: output)
    private var window: NSWindow!
    private let permission = NSTextField(labelWithString: "")
    private let counts = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var starts: [NSButton] = []
    private var timer: Timer?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var activity: NSObjectProtocol?
    private var nextUI: TimeInterval = 0
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 470),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Bongo Tap Lab — F20 验证"; window.delegate = self; window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "F20 / 后台拦截验证")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        counts.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        counts.heightAnchor.constraint(equalToConstant: 66).isActive = true
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        let foreground = button("① 前台 F20 ×100", #selector(startForeground))
        let background = button("② 后台拦截 ×100", #selector(startBackground))
        starts = [foreground, background]
        let instructions = NSTextField(wrappingLabelWithString:
            "每轮倒计时 8 秒；间隔 50–150ms，按住 20ms，本实验关闭额外随机休息。\n① 保持本窗口前台，核对游戏是否 +100。\n② 切换到输入测试窗口，先不打字核对 +100，再另跑一轮测试打字。\n真实键鼠也会被游戏计数，因此打字轮不以游戏只 +100 为标准。")
        let stack = NSStackView(views: [title, permission,
            row([button("打开辅助功能设置…", #selector(authorize)), button("定位验证应用", #selector(reveal))]),
            counts, status, row([foreground, background, button("停止", #selector(stop))]),
            button("打开输入测试窗口", #selector(openReceiver)), instructions])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        setupMenu()
        session.gate = { [weak self] mode in
            guard let self else { return "验证应用已关闭。" }
            guard AccessibilityPermission.isGranted() else { return "当前验证应用未获辅助功能授权。" }
            if mode == .foreground && (!NSApp.isActive || !self.window.isKeyWindow) { return "前台测试失焦，已停止。" }
            return nil
        }
        session.onFinished = { [weak self] in
            guard let self else { return }
            if let activity = self.activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
            probeReport("last-" + self.session.mode.rawValue, self.report())
            self.refresh()
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 && event.type == .keyDown { self.stop(); return nil }
            return self.output.receiveLocal(event)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.session.stop("休眠、锁屏或会话退出，已停止。")
            })
        }
        timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.session.tick()
            if ProcessInfo.processInfo.systemUptime >= self.nextUI {
                self.nextUI = ProcessInfo.processInfo.systemUptime + 0.2; self.refresh()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refresh()
    }

    private func report() -> [String: Any] {
        ["time": ISO8601DateFormatter().string(from: Date()), "mode": session.mode.rawValue,
         "phase": session.phase.rawValue, "permission": AccessibilityPermission.isGranted(),
         "sent": session.sent, "released": session.released, "receivedDown": session.receivedDown,
         "receivedUp": session.receivedUp, "transportPassed": session.passed,
         "gameCounterVerified": false, "message": session.message]
    }

    private func refresh() {
        let granted = AccessibilityPermission.isGranted()
        permission.stringValue = granted ? "● 验证应用已获辅助功能授权" : "● 请单独授权 Bongo Tap Lab"
        permission.textColor = granted ? .systemTeal : .systemOrange
        let receiver = session.mode == .foreground ? "本窗口接收" : "Session 拦截"
        counts.stringValue = "发送 \(session.sent) / 100    松开 \(session.released)\n\(receiver)：按下 \(session.receivedDown) / 松开 \(session.receivedUp)"
        status.stringValue = (session.phase == .countdown ? "\(session.remainingCountdown) 秒后开始。" : "") + session.message
        starts.forEach { $0.isEnabled = !session.busy && granted }
        statusItem.button?.title = session.busy ? "F20 \(session.sent)" : "F20 Lab"
        probeReport("current", report())
    }

    private func start(_ mode: ProbeMode) {
        if session.start(mode) {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Bounded F20 validation")
        }
        refresh()
    }
    @objc private func startForeground() { start(.foreground) }
    @objc private func startBackground() { start(.background) }
    @objc private func stop() { session.stop(); refresh() }
    @objc private func authorize() {
        stop(); AccessibilityPermission.request()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    @objc private func openReceiver() {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Bongo Input Check.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    private func setupMenu() {
        let menu = NSMenu(); let root = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出验证应用", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu; menu.addItem(root); NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let actions = NSMenu()
        for (title, action) in [("停止验证", #selector(stop)), ("显示验证窗口", #selector(show))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; actions.addItem(item)
        }
        statusItem.menu = actions
    }
    private func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
    private func row(_ views: [NSView]) -> NSStackView { let row = NSStackView(views: views); row.spacing = 10; return row }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard session.busy else { return .terminateNow }
        session.stop("应用退出，停止发送。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        session.shutdown(); timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
