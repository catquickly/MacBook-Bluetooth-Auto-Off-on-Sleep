# Auto Turn Off Bluetooth

A menu bar app for MacBook that turns Bluetooth off as you close the lid and back on when you open it past a set angle. Built to reduce Bluetooth activity while the Mac sleeps.

[简体中文](README.zh-CN.md) · [Download v1.2.0](https://github.com/catquickly/MacBook-Bluetooth-Auto-Off-on-Sleep/releases/tag/v1.2.0)

## Requirements

- Apple Silicon MacBook with a compatible hinge angle sensor
- macOS 14 or later
- Intel MacBooks have not been tested

## Install

1. Download the DMG from [Releases](https://github.com/catquickly/MacBook-Bluetooth-Auto-Off-on-Sleep/releases/tag/v1.2.0).
2. Open it and drag **Auto Turn Off Bluetooth** to **Applications**.
3. Launch the app and allow Bluetooth access when prompted.

To update, turn off background activity in the old app and quit it before replacing it. Your saved settings are kept.

The app is ad-hoc signed and has not been notarized by Apple. If macOS blocks it, see Apple's [Open Anyway instructions](https://support.apple.com/en-us/102445).

## Use

The menu bar shows the current lid angle. Use the two sliders to set when Bluetooth turns off and on.

| Action | Default | Range |
| --- | --- | --- |
| Turn off | Lid angle ≤ 10° | 0°–60° |
| Turn on | Lid angle > 130° | 70°–130° |

Between the two thresholds, Bluetooth stays as it is. The menu also lets you enable Open at Login and background activity. With background activity enabled, monitoring continues after the menu bar app quits; turn it off in the menu to stop monitoring.

English and Simplified Chinese are included. Settings are stored locally; the app has no account, analytics, or network service.

## Limitations

Bluetooth accessories disconnect when Bluetooth is turned off. AirDrop and Handoff may also be affected.

The app requests Bluetooth power off before sleep; it does not run continuously while the Mac sleeps. Behavior depends on the MacBook's sensor and macOS version. It uses an undocumented Bluetooth interface that may break after a system update.

No radio or beacon measurements have been made. The app reports the Bluetooth power state from macOS and cannot guarantee that the Mac emits no Bluetooth signals.

## Build

Install Xcode Command Line Tools, then run from the project folder on an Apple Silicon Mac:

```sh
./Scripts/build-and-package.sh
```

The app, background helper, and language resources are packaged into a DMG in `releases/`, alongside a SHA-256 checksum. Finder automation permission may be needed to arrange the installer window.

## License

[MIT](LICENSE) · © 2026 catquickly
