; ============================================================================
; Logic tests for Win11KeyRemapper.ahk - NOT a standalone script.
; tests\run-tests.ps1 appends this file to a patched copy of the app (no
; startup, no hook, side effects replaced by the Test* stubs below) and runs
; it. Fake key events are passed straight to KeyboardProc.
; ============================================================================
Critical                                ; no timer may run in the middle of a test
TOASTS := [], SENT := [], RAN := []
TestToast(title, sub, kind := "ok", holdMs := 5000) {
    TOASTS.Push(title " | " sub)
}
TestSend(keys) => SENT.Push(keys)
TestRun(target, dir := "") => RAN.Push(target)
TestLock(state) => 0
PASSES := 0, FAILS := 0
Check(cond, label) {
    global PASSES, FAILS
    if cond
        PASSES++
    else {
        FAILS++
        FileAppend("FAIL: " label "`n", "*", "UTF-8")
    }
}
Eq(a, b, label) => Check(a == b, label "  got [" a "] expected [" b "]")
Note(text) => FileAppend("note: " text "`n", "*", "UTF-8")

KEV := Buffer(24, 0)
Ev(vk, sc, up := false, injected := false) {
    flags := ((sc & 0x100) ? 1 : 0) | (up ? 0x80 : 0) | (injected ? 0x10 : 0)
    NumPut("uint", vk, KEV, 0), NumPut("uint", sc & ~0x100, KEV, 4), NumPut("uint", flags, KEV, 8)
    return KeyboardProc(0, up ? 0x101 : 0x100, KEV.Ptr)
}
TakeQueue() {
    out := ""
    for a in QUEUE
        out .= a.do (a.HasOwnProp("key") ? ":" a.key : "") (a.HasOwnProp("keys") ? ":" a.keys : "") ";"
    QUEUE.Length := 0
    return out
}
Reset(c) {
    global CFG, PAUSED
    CFG := c, PAUSED := false
    ApplySettings()
    HELD.Clear(), PRESS.Clear(), SWALLOW.Clear(), QUEUE.Length := 0
}

tmp := A_Temp "\kr-test-" A_TickCount
DirCreate(tmp)
SETTINGS_PATH := tmp "\settings.ini"
APP.lnk := tmp "\Windows 11 Key Remapper.lnk"

; ---- 1. Settings file ----
CFG := DefaultSettings()
WriteSettings(SETTINGS_PATH, CFG)
c := LoadSettings(SETTINGS_PATH)
Eq(c.sourceVK, 0xFF, "default SourceVK")
Eq(c.sourceSC, 0x175, "default SourceSC")
Eq(c.matchSC, 1, "default MatchSC")
Eq(c.mode, "NumLock", "default Mode")
Eq(c.targetMods.Length, 0, "default TargetMods empty")
Eq(JoinMods(c.launchMods), "RCtrl", "default LaunchMods")
Eq(c.launchVK, 0xFF, "default LaunchVK")
Eq(c.launchPath, "auto", "default LaunchPath")
Eq(c.showToast, 1, "default ShowToast")
f := FileOpen(SETTINGS_PATH, "r"), enc := f.Encoding, f.Close()
Eq(enc, "UTF-16", "ini encoding")
txt := FileRead(SETTINGS_PATH, "UTF-16")
Check(InStr(txt, "; Windows 11 Key Remapper - settings`r`n"), "header with CRLF")
Check(InStr(txt, "SourceVK=0xFF") && InStr(txt, "TargetMods=`r`n"), "hex + empty values written")

IniWrite("", SETTINGS_PATH, "Launcher", "LaunchMods")
Eq(LoadSettings(SETTINGS_PATH).launchMods.Length, 0, "empty LaunchMods stays empty")
IniDelete(SETTINGS_PATH, "Launcher", "LaunchMods")
Eq(JoinMods(LoadSettings(SETTINGS_PATH).launchMods), "RCtrl", "missing LaunchMods -> default")

p2 := tmp "\roadmap.ini"
FileAppend("[Remap]`r`nSourceVK=0x41          `; key to remap`r`nSourceSC=0x1E`r`nMatchSC=0`r`nMode=key  `; lower case`r`nTargetMods=lctrl, Shift`r`nTargetVK=0x43`r`nTargetSC=junk`r`n[Launcher]`r`nLaunchEnabled=0`r`nLaunchPath=`r`n[General]`r`nShowToast=no`r`n", p2)
c := LoadSettings(p2)
Eq(c.sourceVK, 0x41, "inline comment stripped")
Eq(c.matchSC, 0, "MatchSC=0")
Eq(c.mode, "Key", "mode case-insensitive")
Eq(JoinMods(c.targetMods), "LCtrl,LShift", "mods parsed + aliases")
Eq(c.targetSC, 0, "invalid hex -> default")
Eq(c.launchEnabled, 0, "LaunchEnabled=0")
Eq(c.launchPath, "auto", "empty LaunchPath -> auto")
Eq(c.launchVK, 0xFF, "missing LaunchVK -> default")
Eq(c.showToast, 0, "ShowToast=no")

c := LoadSettings(A_ScriptDir "\..\settings.example.ini"), d := DefaultSettings()
for key in ["sourceVK", "sourceSC", "matchSC", "mode", "targetVK", "targetSC", "launchEnabled"
          , "launchVK", "launchSC", "launchAnySide", "launchPath", "showToast"]
    Eq(c.%key% "", d.%key% "", "settings.example.ini matches defaults: " key)
Eq(JoinMods(c.targetMods) "|" JoinMods(c.launchMods), JoinMods(d.targetMods) "|" JoinMods(d.launchMods), "settings.example.ini mods")

; ---- 2. Labels ----
Eq(FieldText(0xFF, 0x175, ["RCtrl"]), "Right Ctrl + NitroSense key · VK FF SC 175", "field text")
Eq(FieldText(0, 0), "Not set", "field not set")
Eq(KeyLabel(0x41, 0x1E), "A", "letter")
Eq(KeyLabel(0x90, 0x145), "Num Lock", "numlock")
Eq(KeyLabel(0x14, 0x3A), "Caps Lock", "capslock")
Eq(KeyLabel(0x60, 0x52), "Numpad 0", "numpad0")
Eq(KeyLabel(0xB3, 0x122), "Media Play Pause", "media")
Eq(KeyLabel(0x7B, 0x58), "F12", "F12")
Eq(KeyLabel(0xFF, 0x159), "Win Lock on", "win lock")
Eq(KeyLabel(0xFF, 0x1AB), "Special key (SC 1AB)", "unknown vendor key")
Eq(KeyLabel(0xA3, 0x11D), "Right Ctrl", "right ctrl")
Eq(ComboLabel(["LCtrl", "RCtrl"], 0xFF, 0x175, true), "Ctrl + NitroSense key", "any side dedupe")
Eq(Summary(DefaultSettings()), "NitroSense key → Num Lock", "summary")

; ---- 3. Precomputed rules ----
c := DefaultSettings(), c.mode := "Key", c.targetVK := 0x41, c.targetSC := 0x1E
Reset(c)
Eq(RT.down, "{Blind}{vk41sc01E down}", "key down")
Eq(RT.up, "{Blind}{vk41sc01E up}", "key up")
c.targetMods := ["LCtrl", "LShift"]
Reset(c)
Eq(RT.combo, "{LCtrl down}{LShift down}{vk41sc01E}{LShift up}{LCtrl up}", "combo")
c.targetVK := 0
Reset(c)
Eq(RT.mode, "None", "Key without target -> None")

; ---- 4. Hook: default settings ----
Reset(DefaultSettings())
Eq(Ev(0xFF, 0x175), 1, "NitroSense down swallowed")
Eq(TakeQueue(), "toggle:NumLock;", "toggle queued")
Eq(Ev(0xFF, 0x175), 1, "repeat swallowed")
Eq(TakeQueue(), "", "repeat does not toggle")
Eq(Ev(0xFF, 0x175, true), 1, "up swallowed")
Eq(Ev(0xFF, 0x175), 1, "2nd press")
Eq(TakeQueue(), "toggle:NumLock;", "2nd press toggles")
Ev(0xFF, 0x175, true)
Check(Ev(0xFF, 0x159) != 1 && Ev(0xFF, 0x159, true) != 1, "Win Lock on passes")
Check(Ev(0xFF, 0x162) != 1, "Win Lock off passes")
Check(Ev(0xFF, 0x175, false, true) != 1, "injected passes")
Eq(TakeQueue(), "", "nothing queued for passed keys")

REPEAT_MS := 50
Ev(0xFF, 0x175), Sleep(120)
Eq(Ev(0xFF, 0x175), 1, "stale press")
Eq(TakeQueue(), "toggle:NumLock;toggle:NumLock;", "missed key-up: new press toggles again")
REPEAT_MS := 1500
Ev(0xFF, 0x175, true)

Check(Ev(0xA2, 0x1D) != 1, "LCtrl passes")
Check(HELD.Has("LCtrl"), "LCtrl tracked")
Eq(Ev(0xFF, 0x175), 1, "LCtrl+NitroSense")
Eq(TakeQueue(), "toggle:NumLock;", "LCtrl+NitroSense toggles (launcher needs RCtrl)")
Ev(0xFF, 0x175, true), Ev(0xA2, 0x1D, true)
Check(!HELD.Has("LCtrl"), "LCtrl released")

Check(ModsMatch(Map("RCtrl", true)), "RCtrl matches launcher")
Check(!ModsMatch(Map("LCtrl", true)), "LCtrl doesn't match")
Check(!ModsMatch(Map("RCtrl", true, "LShift", true)), "extra modifier doesn't match")
Check(!ModsMatch(Map()), "no modifier doesn't match")
c := DefaultSettings(), c.launchAnySide := true
Reset(c)
Check(ModsMatch(Map("LCtrl", true)), "any side: LCtrl matches")
Check(!ModsMatch(Map("LAlt", true)), "any side: Alt doesn't")

; launcher without modifiers on F13
c := DefaultSettings(), c.launchMods := [], c.launchVK := 0x7C, c.launchSC := 0x64
Reset(c)
Eq(Ev(0x7C, 0x64), 1, "launch key swallowed")
Eq(Ev(0x7C, 0x64), 1, "launch repeat swallowed")
Eq(TakeQueue(), "launch;", "launch queued once")
Eq(Ev(0x7C, 0x64, true), 1, "launch up swallowed")
Check(Ev(0x7D, 0x65) != 1, "F14 passes")

; ---- 5. Hook: other modes ----
c := DefaultSettings(), c.mode := "Key", c.targetVK := 0x41, c.targetSC := 0x1E
Reset(c)
Ev(0xFF, 0x175), Ev(0xFF, 0x175), Ev(0xFF, 0x175, true)
Eq(TakeQueue(), "send:{Blind}{vk41sc01E down};send:{Blind}{vk41sc01E down};send:{Blind}{vk41sc01E up};", "real remap down/repeat/up")
c.targetMods := ["LCtrl"]
Reset(c)
Ev(0xFF, 0x175), Ev(0xFF, 0x175), Ev(0xFF, 0x175, true)
Eq(TakeQueue(), "send:{LCtrl down}{vk41sc01E}{LCtrl up};send:{LCtrl down}{vk41sc01E}{LCtrl up};", "combo on each down, nothing on up")
c.mode := "Disable"
Reset(c)
Eq(Ev(0xFF, 0x175), 1, "disabled key swallowed")
Eq(Ev(0xFF, 0x175, true), 1, "disabled key-up swallowed")
Eq(TakeQueue(), "", "disable does nothing")
c.mode := "None", c.launchEnabled := false
Reset(c)
Check(Ev(0xFF, 0x175) != 1, "mode None passes")
Ev(0xFF, 0x175, true)
c := DefaultSettings(), c.matchSC := false
Reset(c)
Eq(Ev(0xFF, 0x159), 1, "MatchSC=0 also catches Win Lock (expected)")
Ev(0xFF, 0x159, true), TakeQueue()

Reset(DefaultSettings())
PAUSED := true
Check(Ev(0xFF, 0x175) != 1, "paused passes")
Check(Ev(0xFF, 0x175, true) != 1, "paused up passes")
PAUSED := false

; settings change while the key is held: release target, eat physical key-up
c := DefaultSettings(), c.mode := "Key", c.targetVK := 0x41, c.targetSC := 0x1E
Reset(c)
Ev(0xFF, 0x175)
CFG := DefaultSettings()
ApplySettings()
Eq(TakeQueue(), "send:{Blind}{vk41sc01E down};send:{Blind}{vk41sc01E up};", "held target released on apply")
Eq(Ev(0xFF, 0x175, true), 1, "physical key-up eaten after apply")
Eq(TakeQueue(), "", "no toggle on that key-up")

; ---- 6. Capture ----
Reset(DefaultSettings())
StartCap(target) {
    CAP.target := target, CAP.mods := Map(), CAP.downs := Map(), CAP.result := 0, CAP.active := true
}
StartCap("launch")
Eq(Ev(0xA3, 0x11D), 1, "cap: RCtrl down eaten")
Eq(Ev(0xA3, 0x11D), 1, "cap: RCtrl repeat eaten")
Eq(Ev(0xFF, 0x175), 1, "cap: NitroSense eaten")
Check(!CAP.active, "cap: finished on non-modifier")
Eq(CAP.result.vk " " CAP.result.sc " " JoinMods(CAP.result.mods), 255 " " 0x175 " RCtrl", "cap: result")
Eq(TakeQueue(), "", "cap: no action fired")
Eq(Ev(0xFF, 0x175), 1, "cap: repeat after finish eaten")
Eq(Ev(0xFF, 0x175, true), 1, "cap: key-up eaten")
Eq(Ev(0xA3, 0x11D, true), 1, "cap: RCtrl key-up eaten")
Eq(SWALLOW.Count, 0, "cap: swallow list empty")
Eq(TakeQueue(), "", "cap: still no action")

StartCap("source")
Ev(0xA3, 0x11D)
Eq(Ev(0xA3, 0x11D, true), 1, "cap: lone modifier up")
Eq(CAP.result.vk " " CAP.result.sc " " JoinMods(CAP.result.mods), 0xA3 " " 0x11D " ", "cap: lone modifier captured")

StartCap("target")
Check(Ev(0x0D, 0x1C, true) != 1, "cap: key-up of a key pressed before passes")
Ev(0xA2, 0x21D), Ev(0xA5, 0x138), Ev(0x41, 0x1E)
Eq(JoinMods(CAP.result.mods), "RAlt", "cap: AltGr fake LCtrl ignored")
Ev(0x41, 0x1E, true), Ev(0xA5, 0x138, true), Ev(0xA2, 0x21D, true)
Eq(SWALLOW.Count, 0, "cap: AltGr ups eaten")

StartCap("target")
Ev(0xA0, 0x2A)
CaptureCancel()
Eq(Ev(0xA0, 0x2A, true), 1, "cancel: held modifier key-up eaten")
Check(Ev(0xA0, 0x2A) != 1, "cancel: next press works")
Ev(0xA0, 0x2A, true)

; ---- 7. Settings window (hidden) ----
Reset(DefaultSettings())
NS.checked := true, NS.target := ""
ShowSettings()
Check(UI.gui, "gui created")
Eq(UI.srcEdit.Value, "NitroSense key · VK FF SC 175", "gui: source field")
Eq(UI.launchEdit.Value, "Right Ctrl + NitroSense key · VK FF SC 175", "gui: launch field")
Eq(UI.mode.Value, 1, "gui: mode")
Check(!UI.targetBtn.Enabled, "gui: target disabled for toggles")
Check(InStr(UI.hint.Value, "not found"), "gui: hint not found")
CaptureToggle("source")
Eq(UI.srcBtn.Text, "Listening…", "gui: listening label")
Eq(UI.srcEdit.Value, LISTEN_TEXT, "gui: listening text")
CaptureToggle("source")
Check(!CAP.active, "gui: click again cancels")
Eq(UI.srcBtn.Text, "Detect key…", "gui: label restored")
CaptureToggle("source")
CaptureToggle("target")
Eq(CAP.target, "target", "gui: other capture replaces")
CaptureCancel()
CaptureToggle("source")
Ev(0x41, 0x1E)
CaptureDone()
Ev(0x41, 0x1E, true)
Eq(DRAFT.sourceVK, 0x41, "gui: detected source stored in draft")
Eq(UI.srcEdit.Value, "A · VK 41 SC 1E", "gui: source field updated")
Eq(CFG.sourceVK, 0xFF, "gui: CFG untouched until Save")
UI.mode.Value := 4
OnModeChange(UI.mode)
Check(UI.targetBtn.Enabled, "gui: target enabled for Key")
Check(InStr(ValidateSettings(DRAFT), "press instead"), "validate: Key needs target")
d := DefaultSettings(), d.launchMods := []
Check(InStr(ValidateSettings(d), "never run"), "validate: launcher = source without modifier")
d := DefaultSettings(), d.launchVK := 0
Check(InStr(ValidateSettings(d), "shortcut that opens"), "validate: launcher needs shortcut")
d := DefaultSettings(), d.launchPath := "C:\nope\nope.exe"
Check(InStr(ValidateSettings(d), "not found"), "validate: missing app")
Eq(ValidateSettings(DefaultSettings()), "", "validate: defaults ok")
UI.path.Value := "C:\nope\nope.exe"
OnPathChange()
Check(InStr(UI.hint.Value, "File not found"), "gui: custom path hint")
UI.path.Value := "", OnPathChange()
Eq(DRAFT.launchPath, "auto", "gui: empty path = auto")
ResetDraft()
Eq(DRAFT.sourceVK, 0xFF, "gui: reset defaults")
DRAFT.mode := "CapsLock"
UI.launchOn.Value := 0
OnLaunchToggle(UI.launchOn)
Check(!UI.launchBtn.Enabled && !UI.path.Enabled, "gui: launcher controls disabled")
SaveFromGui()
Check(!UI.gui, "gui: closed after save")
Eq(CFG.mode, "CapsLock", "save: applied")
Eq(RT.launchOn, false, "save: launcher off applied")
Eq(LoadSettings(SETTINGS_PATH).mode, "CapsLock", "save: written to ini")
Check(TOASTS.Length && InStr(TOASTS[TOASTS.Length], "Settings saved | NitroSense key → Caps Lock"), "save: toast")
Check(!FileExist(APP.lnk), "save: autostart untouched")

ShowSettings(true)
Eq(UI.autostart.Value, 1, "first run: autostart pre-checked")
SaveFromGui()
Check(FileExist(APP.lnk), "first run: shortcut created")
FileGetShortcut(APP.lnk, &lnkTarget, , &lnkArgs)
Eq(lnkTarget, A_AhkPath, "shortcut runs AutoHotkey")
Eq(lnkArgs, '"' A_ScriptFullPath '"', "shortcut passes the script")

; ---- 8. Tray / pause ----
BuildTray()
Check(InStr(A_IconTip, "Windows 11 Key Remapper`nNitroSense key → Caps Lock"), "tray tooltip")
TogglePause()
Check(PAUSED && InStr(A_IconTip, "(paused)"), "pause on")
TogglePause()
Check(!PAUSED, "pause off")
ToggleAutostart()
Check(!FileExist(APP.lnk), "tray: autostart off")

; ---- 9. NitroSense detection (real machine) ----
Note("NitroSense auto-detect -> [" DetectNitroSense(true) "] " NS.label)
CFG.launchPath := "auto"
LaunchApp()
Note("LaunchApp ran -> [" (RAN.Length ? RAN[RAN.Length] : "") "]")

QUEUE.Length := 0
try DirDelete(tmp, true)
FileAppend(PASSES " passed, " FAILS " failed`n", "*", "UTF-8")
ExitApp(FAILS ? 1 : 0)
