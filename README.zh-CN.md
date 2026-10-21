# Auto Turn Off Bluetooth

一个给 MacBook 用的菜单栏小工具：合盖时关闭蓝牙，开盖超过设定角度后重新开启，减少休眠期间的蓝牙活动。

已知macOS27.0.1及之前版本中未提供“合盖关闭蓝牙“及”睡眠关闭蓝牙“的设置选项，本工具旨在解决此问题。

[English](README.md) · [下载 v1.2.0](https://github.com/catquickly/MacBook-Bluetooth-Auto-Off-on-Sleep/releases/tag/v1.2.0)

## 使用要求

- 配有兼容转轴角度传感器的 Apple Silicon MacBook
- macOS 14 或更高版本
- Intel MacBook 尚未测试

## 安装

1. 在 [Releases](https://github.com/catquickly/MacBook-Bluetooth-Auto-Off-on-Sleep/releases/tag/v1.2.0) 下载 DMG。
2. 打开后，将 **Auto Turn Off Bluetooth** 拖进 **Applications**。
3. 启动应用，按提示允许蓝牙权限。

更新时，先在旧版菜单中关闭“后台常驻”并退出应用，再替换安装。原有设置会保留。

应用使用临时签名（ad-hoc），尚未经过 Apple 公证。如果被 macOS 拦截，可参照[苹果的“仍要打开”说明](https://support.apple.com/zh-cn/102445)。

## 使用

菜单栏显示当前开盖角度，两个滑块分别设置关闭和开启蓝牙的角度。

| 操作 | 默认值 | 可调范围 |
| --- | --- | --- |
| 关闭蓝牙 | 角度 ≤ 10° | 0°–60° |
| 开启蓝牙 | 角度 > 130° | 70°–130° |

两个阈值之间保持当前蓝牙状态。菜单中还可以设置“登录时打开”和“后台常驻”。开启后台常驻后，退出菜单栏应用仍会继续检测；需要停止时，先在菜单中关闭后台常驻。

支持简体中文和英文。设置保存在本机，无需账号，不收集使用数据，也不连接网络服务。

## 已知限制

关闭蓝牙会断开蓝牙键鼠、耳机等配件，也可能影响隔空投送和接力。

应用在进入休眠前请求关闭蓝牙，休眠期间不会持续运行。实际效果取决于 MacBook 的传感器和系统版本；蓝牙控制使用未公开的接口，系统更新后可能失效。

目前没有做射频或信标检测。应用显示的是 macOS 报告的蓝牙电源状态，不能保证 Mac 完全不发出蓝牙信号。

## 从源码构建

在 Apple Silicon Mac 上安装 Xcode 命令行工具，然后在项目目录执行：

```sh
./Scripts/build-and-package.sh
```

脚本会将主程序、后台代理和语言资源打包，在 `releases/` 生成 DMG 和 SHA-256 校验文件。设置安装窗口布局时可能需要 Finder 自动化权限。

## 许可证

[MIT](LICENSE) · © 2026 catquickly
