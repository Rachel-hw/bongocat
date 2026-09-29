# Bongo Tap

Swift / AppKit macOS 前台敲击工具，使用 Core Graphics 发送 A 键，由自己的窗口承接输入。
不修改游戏文件或内存，不读取游戏计数，也没有联网、更新检查或后台键盘记录。

## 当前产物

- 应用：`build/Bongo Tap.app`
- 安装包：`dist/Bongo-Tap-<版本号>-universal.dmg`
- 包含 arm64 / x86_64，最低构建目标 macOS 13。
- 固定采用 ad-hoc 签名，无需 Apple 开发者证书或公证 Secrets。
- 原来的 `build/Bongo Tap Verify.app` 保留为验证原型，正式工具是独立应用，不同时运行。

## 安装与使用

1. 打开 DMG，将 Bongo Tap 拖到 Applications，然后从应用程序启动。
2. 点击“打开权限设置…”，在系统设置的辅助功能中允许 **Bongo Tap**。
   旧验证版 **Bongo Tap Verify** 是另一个应用身份，权限不会自动转移。
   应用每 0.5 秒检测权限，返回窗口也会立即检测；无需退出再打开。
3. 保持游戏运行，设置节奏与本轮目标，点击开始。
4. 保持工具窗口前台。切换应用、窗口失焦、最小化、休眠或锁屏时暂停。
5. 返回后点击“继续敲击”；选择“结束本轮”后可以重新设置参数。
6. Esc 暂停；关闭窗口或退出结束本轮。启动应用本身不会自动发按键。

这是前台模式，暂不支持同时使用其他应用。菜单栏爪印可找回窗口、结束本轮或退出。
每次开始保存合法设置，下一次打开恢复；运行状态不会恢复。

## 节奏与目标

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| 基础间隔 | 100ms | 相邻两次按下的计划间隔，包含 20ms 按住时间 |
| 随机浮动 | ±50ms | 默认均匀随机 50–150ms；允许设置为 0 |
| 暂停概率 | 5% | 每次完成敲击后抽取一次；0 关闭随机休息 |
| 暂停时长 | 500–1500ms | 额外休息，抽取时已松开按键 |
| 本轮目标 | 100 次 | 可改为指定次数、指定分钟，或手动结束 |

开始前倒计时 5 秒，恢复前倒计时 3 秒。
运行时长包含随机休息，不包含倒计时和手动/自动暂停。
暂停会取消未执行的间隔或休息；继续时重新倒计时，累计次数保持不变。
系统调度可能延后事件，工具不会追赶补发。随机节奏不保证无法被检测。

## 100 次计数验证

工具显示的发送次数、释放次数、本窗口收到的事件和游戏计数是四类不同证据。

1. 点击开始后，在倒计时期间读游戏起始值 N（排除点击按钮本身产生的计数）。
2. 保持窗口前台，不操作键鼠。
3. 完成后，在再次操作键鼠之前读结束值 M。
4. 对照发送 100 / 释放 100 / 接收按下 100 / 接收松开 100，且 M − N = 100。

2026-09-29：用户反馈旧的 100 次原型验证通过；未提供前后游戏数字或截图。
正式版沿用相同 CGEvent A 键输入方式，游戏实测结果不由单元测试替代。

0.2.0 本轮检查结果（同日）：

- arm64 与 x86_64 编译、通用可执行文件合并、临时签名校验通过。
- 生命周期模拟检查与 10,000 份随机时间样本通过，未发送真实按键。
- Apple silicon / macOS 26.5.1 实际打开应用，窗口布局、非法间隔拦截、
  次数/时长控件切换、恢复默认和未授权零发送检查通过。
- DMG 校验、只读挂载、Applications 链接及包内签名检查通过；
  从挂载映像运行无输入副作用的检查也通过，包内可执行文件与构建产物一致。
- 新版真实按键与游戏计数、实际锁屏/休眠暂停、Intel 和较旧 macOS 尚未实机验证。

## 构建和打包

需要 Apple Command Line Tools，无外部依赖。

```sh
bash scripts/build.sh
bash scripts/package-dmg.sh
```

构建两个架构并合并通用可执行文件，生成图标与临时签名，随后执行无输入副作用的测试。
安装包包含应用、Applications 快捷方式和中文使用说明；SHA-256 文件在 DMG 旁。

```sh
"build/Bongo Tap.app/Contents/MacOS/BongoTap" --self-test
```

测试使用替代时钟与键盘输出，覆盖精确次数、倒计时、按住时暂停/停止、恢复、过期回调、
失焦、权限缺失与撤销、修饰键、时长上限、创建事件失败、非法参数及随机时间范围。

## 源码布局

- `Sources/TapSettings.swift`：参数约束、随机节奏、设置持久化。
- `Sources/TapRunner.swift`：倒计时、暂停恢复、次数/时间目标和定时任务生命周期。
- `Sources/KeyboardOutput.swift`：成对 CGEvent 创建、系统投递、按键释放。
- `Sources/TapPanel.swift`：原生表单与状态面板。
- `Sources/AppDelegate.swift`：窗口、菜单栏、本地接收计数、休眠/焦点事件。
- `Tests/RunnerChecks.swift`：不发送实际按键的确定性生命周期检查。

## 对外分发

DMG 只是安装容器，不会自动赋予辅助功能权限，也不能替代签名、公证。
当前包传给另一台 Mac 后可能被 Gatekeeper 阻止打开；工具不关闭系统安全保护。
本项目按用户选择保持 ad-hoc 分发，不配置 Apple 签名或公证。
ad-hoc 不提供开发者身份验证；版本更新改变程序签名后，系统可能要求重新授权。
请从固定的 Applications 安装路径启动并授权实际运行的应用，避免混用构建目录与安装目录的副本。
Intel 与旧 macOS 仍需实机验证。

## GitHub Actions 与版本管理

这是单个 Swift 应用，不发布 npm 包，因此不引入 Changesets 和 Node 依赖。
`Resources/Info.plist` 是版本号的唯一来源：应用界面、DMG 文件名、安装说明和 tag 都读取它。
变更说明记录在 `CHANGELOG.md` 的 `Unreleased` 段。

### 日常 CI

推送 `main` 或创建 PR，`CI` 自动执行版本检查、Python 发布脚本测试、Swift 生命周期测试、
双架构构建、ad-hoc 签名和 DMG 打包。安装包保存在 Actions Artifact 中 14 天。
CI 只读仓库，不生成 tag。

### 自动递增版本并打 tag

在 GitHub → Actions → **Release** → **Run workflow**：

1. 选择 `main`；默认增量为 `patch`，只有明确需要时选择 `minor` / `major`。
2. 可填写补充说明，也可以只使用 `CHANGELOG.md` 中已有的 Unreleased 内容。
3. Action 更新应用版本和递增构建号，归档变更说明并提交到 main。
4. 原子推送版本提交和 `vX.Y.Z` tag，构建、打包并上传到 **GitHub Release 草稿**。
5. 检查草稿中的 DMG 和 SHA-256，准备分享时再发布草稿。

自动发版使用仓库自带的 `GITHUB_TOKEN`，不需要个人 PAT。
由于该 Token 创建的 tag 不会再次触发 push 工作流，Release 会直接调用共用构建工作流，
确保不会出现有 tag 却没有安装包的情况。发布过程串行执行；构建失败可重跑失败作业。

### 手动 tag

先更新版本与变更说明、提交并推送，再为该提交创建并推送同版本的 tag。
推送 `v*` tag 会触发 Release；tag 必须严格等于 `v` + Info.plist 的版本号，否则拒绝发布。
手动 tag 不自动修改代码中的版本，避免 tag 所指提交与实际产物不一致。

```sh
python3 scripts/version.py bump                 # 默认 patch；同时归档 Unreleased
python3 scripts/version.py check --tag v0.2.1  # 示例：tag 必须匹配当前版本
```

工作流需要 Actions 启用，以及 Release 作业的 `contents: write` 权限。
如果以后对 main 启用分支保护，禁止机器人直接提交，需改成版本 PR 再合并的流程。
仓库目前为私有；Release 与 Artifact 的访问范围仍受仓库权限限制。

### 权限刷新修复的验证边界

权限显示和执行器统一使用 `AXIsProcessTrusted()`；轮询不请求新权限，只有用户点击授权按钮才弹出提示。
恢复授权不会自动继续已暂停的敲击。模拟测试覆盖同一进程中的未授权 → 授权 → 撤销 → 再授权，
但系统设置开关、macOS TCC 和 ad-hoc 更新后的行为仍需本机实测。

参考：
- https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
