import AppKit

/// Separate foreground process: no global input observation and no injection.
/// It records only F20 counts, never the user's text or other key identities.
final class ReceiverDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let counter = NSTextField(labelWithString: "")
    private let text = NSTextView()
    private var down = 0
    private var up = 0
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Bongo Input Check — 打字测试"; window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "前台输入测试窗口")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let help = NSTextField(wrappingLabelWithString: "后台拦截成功时，下面的 F20 次数应始终为 0 / 0。\n第一轮不要打字，核对游戏增量；第二轮可输入测试文字，尝试中文输入法、Shift 和 Command。输入内容不会写入报告。")
        counter.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        text.isRichText = false; text.font = .systemFont(ofSize: 18)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true; text.autoresizingMask = [.width]
        scroll.documentView = text
        scroll.widthAnchor.constraint(equalToConstant: 642).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 155).isActive = true
        let stack = NSStackView(views: [title, help, counter, scroll, NSButton(title: "清零 F20 计数", target: self, action: #selector(reset))])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24).isActive = true
        stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20).isActive = true
        help.widthAnchor.constraint(equalToConstant: 642).isActive = true
        let menu = NSMenu(); let root = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出输入测试", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu; menu.addItem(root)
        let edit = NSMenuItem(); edit.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"),
                                     ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.keyCode == ProbeTransport.key else { return event }
            if event.type == .keyDown { self.down += 1 } else { self.up += 1 }
            self.refresh(); return nil
        }
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(text)
        NSApp.activate(ignoringOtherApps: true); refresh()
    }
    private func refresh() {
        counter.stringValue = "进入前台窗口的 F20：按下 \(down) / 松开 \(up)"
        probeReport("receiver", ["receivedF20Down": down, "receivedF20Up": up,
                                  "time": ISO8601DateFormatter().string(from: Date())])
    }
    @objc private func reset() { down = 0; up = 0; refresh(); window.makeFirstResponder(text) }
    func applicationWillTerminate(_ notification: Notification) { if let monitor { NSEvent.removeMonitor(monitor) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
