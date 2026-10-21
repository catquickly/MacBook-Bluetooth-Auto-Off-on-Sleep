# Changelog

## 1.2.0 — 2026-10-21

- Added English and Simplified Chinese menu and permission text, selected by macOS language settings.
- Changed author attribution to catquickly.
- Added the app version to the menu; bundle build number is 3.
- Updated both READMEs, privacy scope, supported hardware, installation, and signing explanations.
- Added an MIT license, Git exclusions, and versioned release packaging.
- Kept the sensor matching/report decoding, 120 ms polling, thresholds, saved settings, Bluetooth power control, login items, and background service behavior unchanged from the last 1.1.0 source.

Validation: both executable variants compile; source comparison reverses the presentation-only edits to reproduce the 1.1.0 source exactly; both localization tables and app signatures are checked. The DMG is mounted and inspected without launching the new app.

Not tested in this release: physical lid/sleep switching, RF/beacon emissions, Intel MacBooks, compatibility across MacBook models or macOS releases, and opening a quarantined internet download through Gatekeeper. The running 1.1.0 installation is left untouched.

## 1.1.0 — existing local version

The last local revision introduced the configurable thresholds, login item, background helper, and drag-to-Applications installer. Local saved preferences are retained by 1.2.0.
