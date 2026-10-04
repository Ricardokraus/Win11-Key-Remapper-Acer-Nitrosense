# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/).

## [0.2.0] - Unreleased

First public release.

### Added

- Remap the Acer NitroSense key (VK `FF`, SC `175`) or any other key to: toggle
  Num Lock, Caps Lock or Scroll Lock, press another key or shortcut, or nothing.
- *Exact key match* (scan code matching), so Win Lock (Fn+Win), which shares
  VK `FF`, keeps working.
- Holding the key toggles only once (keyboard auto-repeat is ignored).
- Optional shortcut to open NitroSense (default: Right Ctrl + NitroSense key),
  with auto-detection of the desktop and Microsoft Store versions, or any app
  you choose.
- Settings window with a built-in key detector: click "Change…" and press a key
  or a shortcut. Keys are shown as keycaps with their codes. Changes apply on
  Save, no restart needed.
- Light and dark mode for the settings window and the tray menu: follows
  Windows, or choose one (`Theme` setting). Switches live if Windows changes.
- Notifications: choose the position (top or bottom; center, left or right) and
  the animation (slide, fade or none), try them with "Show a test
  notification", or turn the startup/unlock ones off.
- Tray menu: Settings, Pause remapping, Start with Windows, Check for updates,
  Open settings folder, About, Restart, Exit.
- Option to hide the tray icon. Opening the app again shows the settings of the
  running copy instead of starting a second one.
- Update check: once a day (optional) or on demand. On the exe, "Install"
  downloads the release from GitHub, verifies it against `SHA256SUMS.txt`,
  replaces the exe and restarts; from source it opens the release page.
- "Start with Windows" (shortcut in the Startup folder, also when running from
  source).
- Glass-style notification at startup, after unlocking and when the display
  turns back on.
- `settings.ini` next to the exe (portable), or in `%APPDATA%\Win11KeyRemapper`
  when that folder isn't writable.
- Compiled `Win11KeyRemapper.exe` built by GitHub Actions, with SHA-256 sums
  and optional VirusTotal scan links in the release notes.

[0.2.0]: https://github.com/Ricardokraus/Win11-Key-Remapper/releases/tag/v0.2.0
