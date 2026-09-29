import AppKit

/// AppKit controls keep keyboard focus and accessibility behavior native.
final class TapPanel: NSView {
    let permission = NSTextField(labelWithString: "")
    let countLabel = NSTextField(labelWithString: "0")
    let detail = NSTextField(labelWithString: "准备开始")
    let status = NSTextField(wrappingLabelWithString: "")
    let receiver = NSTextField(labelWithString: "")
    let startButton = NSButton(title: "开始敲击", target: nil, action: nil)
    let pauseButton = NSButton(title: "暂停", target: nil, action: nil)
    let stopButton = NSButton(title: "结束本轮", target: nil, action: nil)
    let authorizeButton = NSButton(title: "打开权限设置…", target: nil, action: nil)
    let permissionHelpButton = NSButton(title: "授权帮助…", target: nil, action: nil)
    let resetButton = NSButton(title: "恢复默认", target: nil, action: nil)
    let finishMode = NSPopUpButton()
    let interval = TapPanel.numberField()
    let jitter = TapPanel.numberField()
    let chance = TapPanel.numberField()
    let pauseMin = TapPanel.numberField()
    let pauseMax = TapPanel.numberField()
    let targetCount = TapPanel.numberField()
    let minutes = TapPanel.numberField()
    var fields: [NSTextField] { [interval, jitter, chance, pauseMin, pauseMax, targetCount, minutes] }

    init(settings: TapSettings) {
        super.init(frame: .zero)
        let heading = NSTextField(labelWithString: "Bongo Tap")
        heading.font = .systemFont(ofSize: 28, weight: .bold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let badge = NSTextField(labelWithString: "前台模式 · \(version)")
        badge.textColor = .secondaryLabelColor
        let title = row([heading, badge])
        let subtitle = label("让小猫继续敲击。保持这个窗口在前台，切换应用时自动暂停。")
        permission.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 54, weight: .semibold)
        countLabel.textColor = .systemTeal
        detail.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        detail.textColor = .secondaryLabelColor
        receiver.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        receiver.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        let rhythmHeading = label("敲击节奏")
        rhythmHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        let modeHeading = label("本轮目标")
        modeHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        finishMode.addItems(withTitles: FinishMode.allCases.map(\.title))
        finishMode.target = self
        finishMode.action = #selector(modeChanged)
        let footnote = NSTextField(wrappingLabelWithString:
            "Esc 暂停 · 每次按住 20ms · 随机休息计入运行时间，手动暂停和倒计时不计入。\n这里显示的是工具发送次数；游戏计数请单独对照。随机节奏不保证无法检测。")
        footnote.font = .systemFont(ofSize: 12)
        footnote.textColor = .secondaryLabelColor
        startButton.bezelColor = .systemTeal
        for button in [startButton, pauseButton, stopButton] { button.controlSize = .large }
        let stack = NSStackView(views: [
            title, subtitle, row([permission, authorizeButton, permissionHelpButton]), separator(),
            row([countLabel, label("次已发送")]), detail, receiver, status,
            row([startButton, pauseButton, stopButton]), separator(),
            row([rhythmHeading, resetButton]),
            row([label("基础间隔", width: 72), interval, label("ms", width: 32), label("随机 ±", width: 65), jitter, label("ms")]),
            row([label("暂停概率", width: 72), chance, label("%", width: 32), label("设为 0 可关闭随机暂停")]),
            row([label("暂停时长", width: 72), pauseMin, label("至", width: 32), pauseMax, label("ms")]),
            separator(), modeHeading,
            row([finishMode, targetCount, label("次"), minutes, label("分钟")]), footnote
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 26),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28)
        ])
        load(settings)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func load(_ settings: TapSettings) {
        zip(fields, [settings.intervalMS, settings.jitterMS, settings.pausePercent,
                     settings.pauseMinMS, settings.pauseMaxMS, settings.count, settings.minutes])
            .forEach { $0.0.stringValue = String($0.1) }
        finishMode.selectItem(at: settings.finishMode.rawValue)
        modeChanged()
    }

    func readSettings() -> TapSettings? {
        let parsed = fields.map { Int($0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parsed.allSatisfy({ $0 != nil }) else {
            status.stringValue = "请输入完整的整数，不能包含文字或小数。"
            return nil
        }
        let values = parsed.map { $0! }
        return TapSettings(intervalMS: values[0], jitterMS: values[1], pausePercent: values[2],
                           pauseMinMS: values[3], pauseMaxMS: values[4],
                           finishMode: FinishMode(rawValue: finishMode.indexOfSelectedItem) ?? .count,
                           count: values[5], minutes: values[6])
    }

    func lockSettings(_ locked: Bool) {
        for field in fields { field.isEnabled = !locked }
        finishMode.isEnabled = !locked
        resetButton.isEnabled = !locked
        if !locked { modeChanged() }
    }

    @objc private func modeChanged() {
        targetCount.isEnabled = finishMode.indexOfSelectedItem == FinishMode.count.rawValue
        minutes.isEnabled = finishMode.indexOfSelectedItem == FinishMode.duration.rawValue
    }

    private static func numberField() -> NSTextField {
        let field = NSTextField(string: "")
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 88).isActive = true
        return field
    }

    private func label(_ text: String, width: CGFloat? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        if let width { label.widthAnchor.constraint(equalToConstant: width).isActive = true }
        return label
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 644).isActive = true
        return box
    }
}
