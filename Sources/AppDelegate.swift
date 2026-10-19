import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var panel: TapPanel!
    private let runner = TapRunner()
    private let permissionMonitor = PermissionMonitor()
    private var monitor: Any?
    private var statusItem: NSStatusItem!
    private var menuStatus: NSMenuItem!
    private var menuPause: NSMenuItem!
    private var menuStop: NSMenuItem!
    private var uiTimer: Timer?
    private var receivedDown = 0
    private var receivedUp = 0
    private var observers: [NSObjectProtocol] = []
    private var activity: NSObjectProtocol?
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenus()
        panel = TapPanel(settings: .load())
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 770),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Bongo Tap"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = panel
        for (button, action) in [
            (panel.startButton, #selector(start)), (panel.pauseButton, #selector(togglePause)),
            (panel.stopButton, #selector(stop)), (panel.authorizeButton, #selector(authorize)),
            (panel.permissionHelpButton, #selector(showPermissionHelp)),
            (panel.resetButton, #selector(resetSettings))
        ] { button.target = self; button.action = action }
        runner.canSend = { [weak self] in
            NSApp.isActive && self?.window.isKeyWindow == true && self?.window.isMiniaturized == false
        }
        runner.onUpdate = { [weak self] in self?.refresh() }
        // This is a local receiver, not a global keyboard logger. Consuming our
        // own events here keeps A out of editable controls and shortcut handling.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 && event.type == .keyDown {
                self.runner.pause()
                return nil
            }
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) == QuartzKeyboard.eventTag else { return event }
            if event.type == .keyDown { self.receivedDown += 1 } else { self.receivedUp += 1 }
            self.refresh()
            return nil
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.runner.pause("已暂停：电脑休眠、锁屏或会话不再活跃。")
            })
        }
        uiTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollPermission()
            self?.runner.checkSafety()
            self?.refreshCounters()
        }
        RunLoop.main.add(uiTimer!, forMode: .common)
        refresh()
        window.center()
        showWindow()
    }

    private func buildMenus() {
        let mainMenu = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 Bongo Tap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu
        mainMenu.addItem(root)
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Bongo Tap")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuStatus = NSMenuItem(title: "尚未开始", action: nil, keyEquivalent: "")
        menuStatus.isEnabled = false
        menu.addItem(menuStatus)
        menu.addItem(.separator())
        for (title, action) in [("显示窗口", #selector(showWindow)), ("暂停", #selector(togglePause)), ("结束本轮", #selector(stop))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            if action == #selector(togglePause) { menuPause = item }
            if action == #selector(stop) { menuStop = item }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Bongo Tap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func refreshCounters() {
        guard panel != nil else { return }
        let elapsed = Int(runner.elapsed)
        panel.countLabel.stringValue = String(runner.sent)
        let target = runner.settings.finishMode == .count ? "目标 \(runner.settings.count) 次" : runner.settings.finishMode == .duration ? "目标 \(runner.settings.minutes) 分钟" : "手动结束"
        panel.detail.stringValue = String(format: "%@  ·  运行 %02d:%02d  ·  随机休息 %d 次", target, elapsed / 60, elapsed % 60, runner.pauseCount)
        if let receipts = runner.receipts {
            panel.receiver.stringValue = "已释放 \(runner.released)  ·  后台已拦截 按下 \(receipts.down) / 松开 \(receipts.up)"
        } else {
            panel.receiver.stringValue = "已释放 \(runner.released)  ·  本窗口收到 按下 \(receivedDown) / 松开 \(receivedUp)"
        }
        menuStatus.title = "已发送 \(runner.sent) 次" + (runner.phase == .paused ? " · 已暂停" : runner.isActive ? " · 运行中" : "")
    }

    private func refresh() {
        guard panel != nil else { return }
        let authorized = permissionMonitor.granted
        panel.permission.stringValue = authorized ? "● 辅助功能已授权" : "● 当前应用未获辅助功能授权"
        panel.permission.textColor = authorized ? .systemTeal : .systemOrange
        panel.status.stringValue = runner.isSettling ? "正在收尾，请稍候…" : runner.message
        panel.startButton.isEnabled = !runner.hasSession
        panel.pauseButton.isEnabled = runner.hasSession && !runner.isSettling
        panel.pauseButton.title = runner.phase == .paused ? "继续敲击" : "暂停"
        panel.stopButton.isEnabled = runner.hasSession
        menuPause.title = runner.phase == .paused ? "继续敲击" : "暂停"
        menuPause.isEnabled = panel.pauseButton.isEnabled
        menuStop.isEnabled = panel.stopButton.isEnabled
        panel.lockSettings(runner.hasSession)
        refreshCounters()
        // Prevent App Nap from delaying this user-requested run, while still
        // allowing system idle sleep (sleep/lock notifications pause the run).
        if runner.isActive || runner.isSettling {
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                                 reason: "Bongo Tap 正在执行用户启动的敲击")
            }
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if terminationPending && !runner.isSettling {
            terminationPending = false
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    private func pollPermission() {
        if permissionMonitor.refresh() {
            runner.authorizationDidChange(granted: permissionMonitor.granted)
            refresh()
        }
    }

    @objc private func start() {
        pollPermission()
        guard let settings = panel.readSettings() else { return }
        if let error = settings.validationError { panel.status.stringValue = error; return }
        window.makeFirstResponder(panel)
        if runner.start(settings) {
            receivedDown = 0; receivedUp = 0
            settings.save()
            refresh()
        }
    }
    @objc private func togglePause() {
        pollPermission()
        if runner.phase == .paused && runner.settings.tapMode == .foreground { showWindow() }
        window.makeFirstResponder(panel)
        if runner.phase == .paused { runner.resume() } else { runner.pause() }
    }
    @objc private func stop() { runner.stop() }
    @objc private func resetSettings() { panel.load(TapSettings()); TapSettings().save() }
    @objc private func authorize() {
        runner.pause("已暂停：正在设置权限。")
        AccessibilityPermission.request()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func showPermissionHelp() {
        runner.pause("已暂停：正在查看授权帮助。")
        let alert = NSAlert()
        alert.messageText = "开关已开启，但仍显示未授权？"
        alert.informativeText = "更新或重新编译后，系统可能仍保存旧版本的授权。请在辅助功能列表中移除旧的 Bongo Tap 条目，再添加当前运行的应用并开启权限。返回后会自动检测。\n\n当前应用：\n\(Bundle.main.bundlePath)"
        alert.addButton(withTitle: "在 Finder 中显示当前应用")
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "关闭")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            } else if response == .alertSecondButtonReturn {
                self?.authorize()
            }
        }
    }
    @objc private func showWindow() {
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidBecomeActive(_ notification: Notification) { pollPermission(); refresh() }
    private func pauseForFocus(_ reason: String) {
        if runner.settings.tapMode == .foreground { runner.pause(reason) }
    }
    func applicationDidResignActive(_ notification: Notification) { pauseForFocus("已暂停：切换到了其他应用。") }
    func windowDidResignKey(_ notification: Notification) { pauseForFocus("已暂停：窗口失去焦点。") }
    func windowWillMiniaturize(_ notification: Notification) { pauseForFocus("已暂停：窗口最小化。") }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        runner.stop()
        guard runner.isSettling else { return .terminateNow }
        terminationPending = true
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        runner.stop()
        uiTimer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
