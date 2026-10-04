# Development notes

Technical notes for contributors: how the app is built, why, and the traps this
project already fell into. Read this before changing the hook or the toast.

## Layout

```
src/Win11KeyRemapper.ahk     the app: settings, hook, detector, tray, settings window
src/lib/GlassToast.ahk       "liquid glass" notification (standalone library)
tests/run-tests.ps1          builds a patched copy of the app and runs tests/tests.ahk
tests/tests.ahk              logic tests (fake key events fed to the hook procedure)
tools/make-icon.ps1          regenerates assets/icon.ico
assets/icon.ico, banner.svg
settings.example.ini         documented defaults (a test checks it matches the code)
.github/workflows/build.yml  syntax check, tests, compile, zip, release on tag v*
```

## Everyday commands

```powershell
# Syntax check without running
AutoHotkey64.exe /ErrorStdOut /Validate src\Win11KeyRemapper.ahk

# Logic tests: no hook is installed, no keys are sent, nothing is shown
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1

# Run from source (close any compiled copy first: two hooks would fight)
AutoHotkey64.exe src\Win11KeyRemapper.ahk

# Regenerate the icon (add -Preview preview.png to see every size)
powershell -ExecutionPolicy Bypass -File tools\make-icon.ps1

# Compile
Ahk2Exe.exe /in src\Win11KeyRemapper.ahk /out dist\Win11KeyRemapper.exe /base C:\path\to\AutoHotkey64.exe
```

When you run from source, `settings.ini` is created in `src\` (gitignored).

The tests patch the app before running it: startup (`Main()`) is removed and
`SendInput`, `Run`, `Set*LockState`, `GlassToast` and `MsgBox` are replaced by
stubs. `run-tests.ps1` refuses to run if one of those patches no longer applies,
so renaming those calls means updating the patch list too.

## How the hook works

A single `WH_KEYBOARD_LL` hook (`KeyboardProc`). For every event:

1. `nCode != 0` → pass. Read `vk`, `sc | ((flags & 1) << 8)` (scan code with the
   extended bit, as shown in AutoHotkey's Key History), `flags`.
2. **Injected** (`flags & 0x10`) → pass. That's our own `SendInput` and lock-key
   toggles; without this a remap could loop.
3. **Swallowed key-ups**: the key-up (and auto-repeats) of a key whose key-down we
   ate is eaten too, otherwise Windows would get an unpaired key-up. Entries go
   stale after `REPEAT_MS` without events, so a missed key-up can't eat a later,
   normal key press.
4. **Detection mode** (settings window listening) → handled by `CaptureKey`.
5. **Modifiers** are tracked in `HELD` by the hook itself (see hardware facts).
   The fake Left Ctrl that AltGr sends (scan code `0x21D`) is ignored.
6. **Paused** → pass.
7. **Keys already being handled** (`PRESS`): a key-up ends the press; a key-down
   within `REPEAT_MS` of the previous one is auto-repeat.
8. **Launcher**: key matches `LaunchVK/SC` and the held modifiers are exactly the
   required set (`LaunchModsHeld` first drops modifiers that `GetKeyState(…, "P")`
   says are up — missed key-ups).
9. **Remap**: key matches the source (`MatchSC` decides whether the scan code must
   match). Always swallowed, so Windows and the vendor software never see it.
10. Otherwise pass.

Rules:

- **Nothing heavy inside the hook.** Actions are pushed to `QUEUE` and run by
  `RunQueue` on a `SetTimer(…, -1)`, which keeps their order. GUI updates from the
  detector also go through a timer (`CaptureDone`).
- **Windows silently removes a low-level hook that doesn't answer in time**
  (`LowLevelHooksTimeout`), and nothing tells the app. AutoHotkey is single
  threaded, so anything slow on the main thread (the Apps-folder lookup, `Run`)
  can cause it. `HookInstall()` creates a new hook before removing the old one and
  is called after those operations, after unlocking, when the display turns on
  and after resuming from sleep.
- `REPEAT_MS` is 1500 ms: it must be longer than the slowest Windows repeat delay
  (1 s). With 500 ms the first auto-repeat could arrive after the window and
  toggle Num Lock a second time.
- Toggles act on key-down only and ignore auto-repeat. `Mode=Key` without
  modifiers is a real remap (`{Blind}{vkXXscYYY down}` / `up`), so holding repeats
  and Shift+source gives Shift+target. With modifiers, the whole combo is sent on
  every key-down.
- Changing settings or pausing while a key is held calls `ReleasePresses()`: it
  sends the key-up of a held target key and marks the physical key-up to be eaten.

### Key detector

- Modifier key-down → remembered and swallowed.
- Non-modifier key-down → finishes with the held modifiers (ignored for the key to
  remap).
- Modifier key-up with nothing else pressed → that modifier is the key, so keys
  like Right Ctrl can be remapped.
- Key-ups of keys pressed *before* listening started are let through (e.g. the
  Enter that clicked the button).
- On finish or cancel, every key still held is added to the swallow list.
- It runs before the rules and even while paused, so the NitroSense key itself can
  be detected. 10 s timeout; clicking the button again cancels.

## Hard-won facts about the hardware (Acer Nitro V 16S AI, ANV16S-41)

- The NitroSense key reports **VK `0xFF`, SC `0x175`**. Other Acer keys share
  VK `0xFF`: **Win Lock on (Fn+Win) = SC `0x159`**, **Win Lock off = SC `0x162`**.
  Matching by VK only made Win Lock toggle Num Lock. Hence `MatchSC=1`.
- In early tests the key seemed to report SC `0x145` sometimes. That was almost
  certainly the Num Lock key (`VK 90 SC 145`) injected by the script itself.
- AutoHotkey hotkeys on the raw scan code (`$sc175::`) gave double toggles and are
  fragile → the DllCall hook.
- Returning `1` for the key is required: if Acer's software also handles it, Num
  Lock toggles twice.
- `GetKeyState()` for Ctrl/Alt is unreliable while an elevated window (Task
  Manager) has the focus (UIPI), in both logical and physical mode → modifiers are
  tracked in the hook. Even so, a non-elevated hook simply doesn't receive keys
  while an elevated window is focused. **Accepted limitation.** Do not add
  self-elevation or a "run with highest privileges" scheduled task: self-elevation
  broke autostart because the UAC prompt can't be answered at logon.
- Acer Quick Access (`QAAdmin`) shows its own Caps/Num Lock overlay. NitroSense
  needs Quick Access, so it can't be removed. Out of scope.
- **Autostart:** a shortcut in `shell:startup` pointing to the `.ahk` did **not**
  start at logon (the `.ahk` association isn't ready yet). The shortcut must run
  `AutoHotkey64.exe "script.ahk"`, or the compiled exe. `SetAutostart()` does that
  and recreates the shortcut on every launch, in case the app was moved.
- NitroSense's desktop install lives in
  `%ProgramFiles%\NitroSense\Prerequisites\NitroSenseLauncher.exe` on the test
  laptop. The Store version is found through `shell:AppsFolder`.

## AutoHotkey v2 pitfalls already hit here

1. **Variable names are case-insensitive.** `S` (DPI scale) and `s` (a parameter)
   were the same variable, so the toast icon was scaled by the DPI and overflowed.
   Never use pairs like `S/s`, `W/w`, `H/h`, `B/b`, `R/r` in one function — and
   don't name a local like a global (`held` *is* `HELD`).
2. **Reserved words** can't be variables: `is`, `in`, `and`, `or`, `not`,
   `contains`, `super`, `unset`, `this`.
3. **`DllCall("lib\Func")` unloads the DLL after the call if it wasn't loaded.**
   Handles from `pdh`, `winmm` (`timeBeginPeriod`), `wtsapi32` and `gdiplus` broke
   until `DllCall("LoadLibrary", …)` was added at startup.
4. **Timers can interrupt other threads between lines.** Use `Critical` in hook
   callbacks and animation steps; when swapping resources (like the hook), create
   the new one before freeing the old one.
5. **No heavy or GUI work inside the low-level hook** (see above).
6. **Closures capturing loop variables / nested closures** didn't fire reliably for
   the old Gui toast → toast state lives in a global object (`GT`).
7. **Default parameter values must be literals** in v2.0 (`mods := []` is a syntax
   error; use `0` and replace it inside).
8. **DPI:** the app is system-DPI-aware. The toast switches the thread to
   Per-Monitor v2 (`SetThreadDpiAwarenessContext(-4)`) only while building and
   animating, then restores it; otherwise the screen capture on a monitor with a
   different scale came out black. Don't make the whole thread PMv2: the settings
   window would break on the second monitor.
9. In Git Bash, `/ErrorStdOut` and `/Validate` get converted to paths
   (`C:/Program Files/Git/ErrorStdOut`). Call AutoHotkey from PowerShell or cmd.

## The glass toast

Design (user preferences): rounded card, not a pill; concentric icon tile (icon
radius = card radius − margin); glass = blurred capture of what's behind
(blur 60, saturation 1.3) with a tint per theme; light/dark theme from the
background's luminance (the light theme uses softer colors). It slides down from
the top center of the monitor under the mouse with a small overshoot, holds, and
slides up while fading. Click dismisses it with the same animation.

Shown at startup, on session unlock (`WTS_SESSION_UNLOCK`) and when the display
turns back on without a password (`GUID_CONSOLE_DISPLAY_STATE` 0 → 1, only if the
session isn't locked, so it never shows twice). Hidden on lock / display off.

Performance (measured with a telemetry build before optimizing):

- The cost came from redrawing the shadow every frame, blurring at full
  resolution, and recomposing/re-uploading the bitmap every frame.
- Now it draws **once**, frees every GDI+ object (and calls `GdiplusShutdown`),
  then only moves/fades the layered window with `UpdateLayeredWindow` **without a
  bitmap** (`hdcSrc = NULL`). dwm.exe GPU use went back to idle.
- AutoHotkey timers can't go below ~15.6 ms even with `timeBeginPeriod(1)` → about
  60 fps. A custom loop was rejected (risky next to the hook). `timeBeginPeriod`
  is only active while animating.
- A "live" glass (recapturing every 40 ms) was tried and rejected: choppy at
  180 Hz and +13 % CPU.

## Things tried and rejected

- Hotkeys on the scan code (`$sc145::`, `$sc175::`) with `Send "{NumLock}"`:
  double toggles, fragile.
- Self-elevation at startup: broke autostart (UAC at logon).
- Matching only VK `0xFF`: caught Win Lock.
- A separate key-probe tool: annoying and filled the screen → the detector lives
  in the settings window.
- No auto-repeat filter: holding the key toggled many times.

## Manual test checklist

The tests cover the logic; this needs real keys:

- [ ] NitroSense key → Num Lock toggles once per press, also when held.
- [ ] Win Lock (Fn+Win) still works and doesn't touch Num Lock.
- [ ] Right Ctrl + NitroSense key opens NitroSense; Left Ctrl + key toggles.
- [ ] *Detect…* captures a single key, a combo, and a lone modifier (Right Ctrl).
- [ ] `Mode=Key`: holding the key repeats the target; Shift+key gives Shift+target.
- [ ] Save applies without restarting; Cancel discards.
- [ ] Pause / resume from the tray.
- [ ] Start with Windows: sign out and in, the app starts (exe and source).
- [ ] Toast at startup, after unlock (Win+L) and after the display turns off/on.
- [ ] Toast on a second monitor with a different scale isn't black.
- [ ] Settings window on both monitors looks right.

## Releasing

1. Bump the version in `src/Win11KeyRemapper.ahk` (`;@Ahk2Exe-SetVersion` **and**
   `APP.version`) and add a section to `CHANGELOG.md`.
2. Commit, then tag and push: `git tag v0.2.0` and `git push origin main --tags`.
3. The workflow refuses a tag that doesn't match `SetVersion`, builds, and
   publishes the release with the zip and `SHA256SUMS.txt`.

## Ideas for later (v0.3+)

Multiple remap rules, Spanish UI, a community model list, update check, code
signing (look into free signing programs for open source).
