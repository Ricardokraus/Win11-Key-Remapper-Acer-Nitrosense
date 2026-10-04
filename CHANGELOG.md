# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-10-04

First public release.

### Added

- Remap the Acer NitroSense key (VK `FF`, SC `175`) or any other key to: toggle
  Num Lock, Caps Lock or Scroll Lock, press another key or shortcut, or nothing.
- Exact scan code matching, so Win Lock (Fn+Win), which shares VK `FF`, keeps
  working.
- Holding the key toggles only once (keyboard auto-repeat is ignored).
- Optional shortcut to open NitroSense (default: Right Ctrl + NitroSense key),
  with auto-detection of the desktop and Microsoft Store versions, or any app
  you choose.
- Settings window with a built-in key detector: click "Detect…" and press a
  key or a shortcut. Changes apply on Save, no restart needed.
- Tray menu: Settings, Pause remapping, Start with Windows, Open settings
  folder, About.
- "Start with Windows" (shortcut in the Startup folder, also when running from
  source).
- Glass-style notification at startup, after unlocking and when the display
  turns back on.
- `settings.ini` next to the exe (portable), or in `%APPDATA%\Win11KeyRemapper`
  when that folder isn't writable.
- Compiled `Win11KeyRemapper.exe` built by GitHub Actions, with SHA-256 sums.

[0.2.0]: https://github.com/Ricardokraus/Win11-Key-Remapper/releases/tag/v0.2.0
