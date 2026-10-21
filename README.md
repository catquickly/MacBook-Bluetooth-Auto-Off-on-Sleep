# Auto Turn Off Bluetooth

**Version 1.2.0 · macOS menu bar app · Made by catquickly**

[简体中文](README.zh-CN.md)

Auto Turn Off Bluetooth is for **MacBook users** who want more control over Bluetooth and their personal privacy. It reads the screen hinge angle and requests that macOS turn Bluetooth off as the lid closes, before normal sleep, then turns Bluetooth on when the lid opens past the configured angle.

The privacy goal is to keep Bluetooth powered off during sleep and reduce Bluetooth advertising and beacon exposure. **This is a design goal, not a verified guarantee of radio silence.** The app checks the Bluetooth power state reported by macOS; it does not measure radio transmissions. Firmware, Find My, and behavior during sleep may vary by MacBook and macOS version. No RF/beacon testing has been performed. Do not rely on this app as proof that a device emits no Bluetooth signals.

## Requirements

- A MacBook with a compatible hinge angle sensor.
- The supplied installer is **Apple Silicon (arm64) only**, for macOS 14 or later.
- **Intel MacBook compatibility has not been tested.** There is no Intel installer in this release. Desktop Macs are outside the intended scope.
- The app uses an undocumented Bluetooth power setter. A future macOS update may change or remove it.

## Behavior

| Setting | Default | Adjustable range |
| --- | --- | --- |
| Turn Bluetooth off | Hinge angle ≤ 10° | 0°–60° |
| Turn Bluetooth on | Hinge angle > 130° | 70°–130° |

At angles between the two thresholds, the app leaves Bluetooth unchanged. Exactly 130° does not trigger the default on rule. Existing saved preferences are retained; the defaults apply to a new installation without saved preferences.

- The menu bar displays the current hinge angle.
- Change both thresholds with the menu sliders.
- Open at Login uses the macOS login item service.
- Background activity uses a separate Launch Agent. If enabled and approved by macOS, it can continue monitoring after the menu bar app quits. Turn background activity off in the menu to stop this behavior, then quit the app.
- Normal system sleep is allowed. Ordinary app execution and sensor polling pause while the Mac sleeps, so the off request must happen before sleep. The app does not continuously monitor the sensor during sleep.
- English and Simplified Chinese are included. macOS selects the interface language from your preferred languages. You can also use System Settings > General > Language & Region > Applications to choose an app language.
- Settings stay on the Mac. There is no account, analytics, or app network service.

Turning Bluetooth off disconnects Bluetooth accessories and can interrupt AirDrop, Handoff, and other features. Use the built-in keyboard and trackpad when testing. Sensor availability and sleep timing need to be checked on each MacBook; they are not guaranteed across models.

## Install

1. Open `Auto Turn Off Bluetooth-1.2.0-arm64.dmg`.
2. Drag **Auto Turn Off Bluetooth.app** to **Applications**.
3. For an update, turn off background activity and quit the old app before replacing it. Open the new copy from Applications.
4. Allow Bluetooth access when macOS asks. Enable Open at Login or background activity only if you want them. macOS may require approval in General > Login Items (or Login Items & Extensions).

The running copy is not replaced by building or downloading a release. The bundle identifier remains `com.codex.hingebluetooth`, preserving the preference domain and service identifiers used by 1.1.0.

## Signing and notarization

This build has a **local ad-hoc code signature**. That seals its code and resources so `codesign --verify` can detect changes, but it does **not** identify an Apple-verified developer. It has **not been notarized** by Apple. A valid local signature is not a malware review or a guarantee that Gatekeeper will allow a downloaded copy.

macOS may warn when opening the downloaded app. Only if you trust the source and have checked the download, follow Apple's [Open Anyway instructions](https://support.apple.com/en-us/102445) in System Settings > Privacy & Security. Do not disable Gatekeeper or SIP globally.

A public Developer ID release requires the author's Apple Developer credentials and certificate, followed by Apple's notarization process. Those credentials are not included in this repository. This release does not claim Developer ID signing or notarization.

## Build from source

Install Xcode Command Line Tools. On an Apple Silicon Mac, run:

```sh
./Scripts/build-and-package.sh
```

The script compiles the app and background helper, copies both languages, applies ad-hoc signatures, verifies them, and creates a versioned DMG and SHA-256 file in `releases/`. DMG window layout requires Finder automation permission. Existing output files are not silently overwritten. Build caches and temporary app bundles stay outside the source folder and are cleaned up after the build.

For a local app bundle without creating a DMG:

```sh
./Scripts/build-and-package.sh --app-only /absolute/path/AutoTurnOffBluetooth.app
```

`Package.swift` describes the executable for development; use the script to produce the complete app bundle with its helper, launch configuration, and language resources.

## GitHub upload

Upload the source folders, scripts, README files, `Package.swift`, `LICENSE`, `.gitignore`, and `CHANGELOG.md`. Keep `releases/` out of source control. Attach only the current versioned DMG and its checksum file to a GitHub Release. The local `releases/archive/` installer is a rebuilt 1.1.0 rollback copy of the previously installed app; it is not the original historical DMG and should not be published as the current release.

`.gitignore` works with Git; a browser file upload does not automatically apply its exclusions. Do not drag the entire desktop folder into GitHub's Upload files page. Use the separately prepared source archive, or Git/GitHub Desktop.

## License

[MIT](LICENSE). Copyright © 2026 catquickly. The software is provided as-is, without warranty. See [CHANGELOG.md](CHANGELOG.md) for this release's scope and validation limits.
