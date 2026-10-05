# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/).

## [0.2.0] - Unreleased

First public release.

### Added

- Remap the Acer NitroSense key (VK `FF`, SC `175`) or any other key to another
  key or shortcut (Num Lock by default), or make it do nothing. When the action
  doesn't press a key, the *Sends* row disappears.
- *Exact key match* (scan code matching), so Win Lock (Fn+Win), which shares
  VK `FF`, keeps working.
- Holding the key toggles Num, Caps or Scroll Lock only once; other keys repeat
  like the real key.
- Optional shortcut to open NitroSense (default: Right Ctrl + NitroSense key),
  with auto-detection of the desktop and Microsoft Store versions, or any app
  you choose.
- Settings window in the Windows 11 style: a sidebar with General, Keys,
  Notifications, Updates, Advanced and About; setting cards with a description
  and, where useful, an ⓘ tooltip. Every change is applied and saved at once; if
  something is missing, the row says what.
- Custom-drawn buttons, switches and sidebar with hover and pressed states and
  small animations: buttons sink onto their edge when pressed, switches slide,
  the selected section's bar grows in. The hand cursor shows over everything
  clickable. Animations follow Windows' *Animation effects* setting.
- *General* → *App*: Restart and Exit buttons, in red.
- *About*: the app card opens the GitHub page; *Feedback* (works on my laptop,
  report a bug, suggest a feature) and *Help* (FAQ, ask a question).
- Built-in key detector: click "Change…" and press a key or a shortcut. Keys are
  shown as keycaps, with their codes below the row title. Ctrl + Num Lock is
  detected as that (Windows reports it as Pause).
- Light and dark mode for the settings window and the tray menu: follows
  Windows, or choose one (`Theme` setting). Switches live if Windows changes.
- Sharp on every monitor: the settings window and the tray menu follow each
  monitor's scale (Per-Monitor DPI v2), also when moved between monitors. Moving
  the window to a monitor with another scale relays out only what's visible, in
  one batch; every bigger change (switching sections, the new scale) is composed
  off-screen first and shown in one copy: no flicker, no half-drawn or black
  frames. While dragging it to another monitor, the window keeps up with the
  mouse (its picture is scaled at once) and gets sharp when you drop it.
- Message boxes (Reset, install an update) and *Browse…* are sharp on every
  monitor too.
- Notifications: when (always, only when the app starts, or never), where (top or
  bottom; center, left or right), how (slide, fade or none) and whether they're
  frosted glass or a solid card in the settings window's colors (*Transparency
  effects*, `ToastTransparency`: lighter for older or low-power PCs), with a
  preview. *Never* means no notifications on the desktop at all, except warnings.
- What you do in the settings window is confirmed inside it: a small solid
  notice rises from the bottom ("Theme: Dark · Saved", the result of *Check
  now*…), can't be clicked away and follows the window. It's independent from
  the desktop notifications: one never replaces the other.
- *Restart* from the settings window reopens it in the same section and place.
- Tray menu: Settings, Pause remapping, Restart, Exit.
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
