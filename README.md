# Bongo Tap

一个用于 Bongo Cat 的 macOS 自动敲击工具。设置节奏和目标次数，让小猫继续敲击。

[下载安装包](https://github.com/Rachel-hw/bongocat/releases) · [更新日志](CHANGELOG.md) · [反馈问题](https://github.com/Rachel-hw/bongocat/issues)

## 功能

- 自定义敲击间隔、随机浮动和随机休息。
- 按次数、按时长运行，或手动停止。
- 支持暂停和继续，自动保存设置。
- 切换应用、最小化、休眠或锁屏时自动暂停。

需要 **macOS 13 或更新版本**，安装包同时包含 Apple silicon 和 Intel 架构。

## 安装

1. 在 [Releases](https://github.com/Rachel-hw/bongocat/releases) 下载 `.dmg` 安装包。
2. 打开 DMG，将 **Bongo Tap** 拖入 **Applications（应用程序）**，然后从应用程序启动。
3. 点击 **打开权限设置…**，在 **系统设置 → 隐私与安全性 → 辅助功能** 中开启 Bongo Tap。
4. 返回应用，确认显示 **辅助功能已授权**。

当前安装包未经过 Apple 公证，首次打开可能被 macOS 拦截。请确认下载来源后，参考
[Apple 的打开说明](https://support.apple.com/zh-cn/102445)。

## 使用

1. 保持 Bongo Cat 正常运行。
2. 在 Bongo Tap 中设置敲击节奏和本轮目标，点击 **开始敲击**。
3. 等待 5 秒倒计时，保持 Bongo Tap 窗口在前台。

默认发送 **100 次**，间隔 **100ms ±50ms**；每次敲击后有 **5%** 的概率休息 **500–1500ms**。
这些参数都可以在窗口中调整。

- 按 **Esc** 或点击 **暂停**，可暂时停止。
- 点击 **继续敲击**，3 秒倒计时后继续，累计次数保留。
- 点击 **结束本轮**，可重新设置参数；关闭窗口也会结束运行。

**目前仅支持前台模式**，切换到其他应用会自动暂停。工具显示的是发送次数，游戏计数请单独对照。
随机节奏不保证无法被游戏检测。

## 常见问题

### 辅助功能开关已开启，为什么仍显示未授权？

更新应用后，系统可能仍保存旧版本的授权。请在辅助功能列表中移除旧的 **Bongo Tap** 条目，
再点加号添加 **应用程序** 中的 Bongo Tap 并开启权限。返回应用后会自动刷新状态。

如果不确定正在运行哪一份应用，可点击 **授权帮助…**，查看路径或在 Finder 中定位。

### 可以一边使用其他应用，一边自动敲击吗？

目前不支持。请保持 Bongo Tap 在前台；返回窗口后，点击 **继续敲击** 即可恢复。

## 从源码构建

需要 macOS 和 Apple Command Line Tools。

```sh
bash scripts/build.sh
bash scripts/package-dmg.sh
```

应用生成在 `build/Bongo Tap.app`，安装包生成在 `dist/`。
维护者发布版本请参阅 [发布指南](docs/RELEASING.md)。
