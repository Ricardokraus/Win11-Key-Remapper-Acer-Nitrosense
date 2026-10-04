#Requires AutoHotkey v2.0
#SingleInstance Off                     ; handled in Main(): a 2nd launch opens the settings
Persistent

;@Ahk2Exe-SetName Windows 11 Key Remapper
;@Ahk2Exe-SetDescription Windows 11 Key Remapper
;@Ahk2Exe-SetVersion 0.2.0
;@Ahk2Exe-SetCopyright Copyright (c) 2026 Ricardo - MIT License
;@Ahk2Exe-SetOrigFilename Win11KeyRemapper.exe
;@Ahk2Exe-SetMainIcon ..\assets\icon.ico

; ============================================================================
; Windows 11 Key Remapper (NitroSense Key Remapper)
; https://github.com/Ricardokraus/Win11-Key-Remapper - MIT License
;
; Remaps the Acer NitroSense key (or any other key) with a single low-level
; keyboard hook (WH_KEYBOARD_LL), plus an optional shortcut that opens the
; NitroSense app. Settings live in settings.ini and are edited from a small
; window opened from the tray icon.
;
; Why it is built like this (details in docs/DEVELOPMENT.md):
; - The NitroSense key reports VK 0xFF, which AutoHotkey can't hotkey
;   reliably, and other Acer keys share that VK (Win Lock on/off). So keys
;   are matched by VK + scan code inside our own hook.
; - The hook swallows the source key so Windows and the vendor software
;   never see it (that used to cause double toggles).
; - Modifiers are tracked by the hook itself: GetKeyState is unreliable for
;   them in some situations.
; - The hook never does real work: actions go through a queue that runs on
;   a timer. Windows silently removes hooks that respond too slowly.
; ============================================================================

#Include %A_ScriptDir%\lib\GlassToast.ahk

APP := {name: "Windows 11 Key Remapper", short: "Key Remapper", version: "0.2.0"
      , repo: "https://github.com/Ricardokraus/Win11-Key-Remapper"
      , api: "https://api.github.com/repos/Ricardokraus/Win11-Key-Remapper/releases/latest"
      , lnk: A_Startup "\Windows 11 Key Remapper.lnk"
      , dataDir: A_AppData "\Win11KeyRemapper"}

; Finding the running copy: its hidden main window gets this title, and a
; second launch posts it INSTANCE_MSG ("open your settings") before exiting.
INSTANCE_TITLE := "Win11KeyRemapper.Instance"
INSTANCE_MSG := DllCall("RegisterWindowMessage", "str", "Win11KeyRemapper.ShowSettings", "uint")

; A key-down that arrives this soon after the previous one, without a key-up
; in between, is keyboard auto-repeat. Must exceed the longest Windows repeat
; delay (1 s), otherwise holding the key would toggle twice.
REPEAT_MS := 1500

MODES       := ["NumLock", "CapsLock", "ScrollLock", "Key", "Disable", "None"]
MODE_LABELS := ["Toggle Num Lock", "Toggle Caps Lock", "Toggle Scroll Lock"
              , "Press another key or shortcut", "Do nothing (disable the key)", "Keep its normal behavior"]
ACTION_INFO := Map("NumLock", "Each press turns Num Lock on or off. Holding the key toggles only once."
                 , "CapsLock", "Each press turns Caps Lock on or off. Holding the key toggles only once."
                 , "ScrollLock", "Each press turns Scroll Lock on or off. Holding the key toggles only once."
                 , "Disable", "The key does nothing at all."
                 , "None", "The key works as it normally would. The shortcut below still works.")
THEME_PREFS := ["System", "Light", "Dark"]
TOAST_POSITIONS := ["TopCenter", "TopRight", "TopLeft", "BottomCenter", "BottomRight", "BottomLeft"]
TOAST_POSITION_LABELS := ["Top center", "Top right", "Top left", "Bottom center", "Bottom right", "Bottom left"]
TOAST_ANIMS := ["Slide", "Fade", "None"]
TOAST_ANIM_LABELS := ["Slide in", "Fade in", "None (just appear)"]
TOAST_WHENS := ["Always", "Startup", "Never"]
TOAST_WHEN_LABELS := ["Always", "Only when the app starts", "Never"]

; Settings window sections: id, title, Segoe Fluent Icons / MDL2 glyph
PAGES := [["general", "General", 0xE713], ["keys", "Keys", 0xE765], ["notifications", "Notifications", 0xEA8F]
        , ["updates", "Updates", 0xE895], ["advanced", "Advanced", 0xE90F], ["about", "About", 0xE946]]
LINKS := [["Report a bug", "/issues/new?template=bug_report.yml"]
        , ["Suggest a feature", "/issues/new?template=feature_request.yml"]
        , ["Tell us it works on your laptop", "/issues/new?template=works_on_my_laptop.yml"]
        , ["Ask a question", "/issues/new?template=question.yml"]
        , ["Project page on GitHub", ""]]
FAQ_TEXT := "
(
My antivirus or SmartScreen warns about the exe
Apps made with AutoHotkey are often flagged by heuristics, and this one watches the keyboard like a keylogger would. It's a false positive: the exe is built by GitHub Actions from the public source, and each release lists SHA-256 sums. For SmartScreen, click More info > Run anyway once.

It doesn't work while Task Manager is in front
Windows doesn't pass keys to normal apps while an admin app is focused. The app runs without admin rights on purpose, so it can start silently at logon.

I hid the tray icon. How do I get here again?
Open the app again: the running copy shows this window instead of starting a second one.

Does it connect to the internet?
Only to check GitHub for updates (Updates section), and to download one when you install it. Nothing about you or your keys is sent.

Does it work on other laptops?
Yes, for any key Windows can see: Keys > Change... next to Key, then press it. Keys handled by the firmware (like Fn) can't be remapped.

How do I uninstall it?
Turn off Start with Windows, then ... > Exit app, and delete the app's folder (and %APPDATA%\Win11KeyRemapper if it exists).
)"

; Settings window colors (RGB). "dim" is used for disabled rows.
THEMES := Map("light", {dark: false, win: 0xF3F3F3, card: 0xFFFFFF, border: 0xE3E3E3, navSel: 0xE6E6E6
                      , text: 0x1A1A1A, sub: 0x616161, dim: 0xA8A8A8
                      , on: 0x1E9E48, knobOn: 0xFFFFFF, off: 0x8A8A8A, knobOff: 0x616161
                      , keyFace: 0xFAFAFA, keyEdge: 0xCFCFCF, keyShade: 0xC9C9C9, keyText: 0x1A1A1A
                      , accent: 0x1E9E48, ok: 0x13803A, warn: 0xC42B1C}
            , "dark", {dark: true, win: 0x202020, card: 0x2B2B2B, border: 0x3A3A3A, navSel: 0x2D2D2D
                      , text: 0xF3F3F3, sub: 0xABABAB, dim: 0x6B6B6B
                      , on: 0x30D158, knobOn: 0x0F2A17, off: 0x9E9E9E, knobOff: 0xCFCFCF
                      , keyFace: 0x3D3D3D, keyEdge: 0x505050, keyShade: 0x171717, keyText: 0xF3F3F3
                      , accent: 0x30D158, ok: 0x6CCB5F, warn: 0xFF99A4})

; Side-specific modifiers, in display order
MOD_ORDER  := ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"]
MOD_VK     := Map("LCtrl", 0xA2, "RCtrl", 0xA3, "LAlt", 0xA4, "RAlt", 0xA5
                , "LShift", 0xA0, "RShift", 0xA1, "LWin", 0x5B, "RWin", 0x5C)
VK_MOD     := Map(0xA2, "LCtrl", 0xA3, "RCtrl", 0xA4, "LAlt", 0xA5, "RAlt"
                , 0xA0, "LShift", 0xA1, "RShift", 0x5B, "LWin", 0x5C, "RWin"
                , 0x11, "LCtrl", 0x12, "LAlt", 0x10, "LShift")      ; generic VKs -> left side
MOD_FAMILY := Map("LCtrl", "Ctrl", "RCtrl", "Ctrl", "LAlt", "Alt", "RAlt", "Alt"
                , "LShift", "Shift", "RShift", "Shift", "LWin", "Win", "RWin", "Win")
MOD_LABEL  := Map("LCtrl", "Left Ctrl", "RCtrl", "Right Ctrl", "LAlt", "Left Alt", "RAlt", "Right Alt"
                , "LShift", "Left Shift", "RShift", "Right Shift", "LWin", "Left Win", "RWin", "Right Win")
MOD_ALIAS  := Map("ctrl", "LCtrl", "control", "LCtrl", "alt", "LAlt", "shift", "LShift", "win", "LWin")

; Acer keys that share VK 0xFF ("VK:SC", hex, SC with the extended bit)
KNOWN_KEYS := Map("FF:175", "NitroSense key", "FF:159", "Win Lock on", "FF:162", "Win Lock off")
KEY_NAMES  := Map("Numlock", "Num Lock", "AppsKey", "Menu key")

INI_HEADER := "
(
; Windows 11 Key Remapper - settings
; Change them from the tray icon > Settings..., or edit this file and restart the app.
; VK = virtual-key code, SC = scan code (hex). The settings window shows them next to each key.
; Mode: NumLock | CapsLock | ScrollLock | Key | Disable | None
; Modifiers (comma-separated): LCtrl RCtrl LAlt RAlt LShift RShift LWin RWin
; LaunchPath: auto, a path to an .exe or .lnk, or shell:AppsFolder\<AppID>
; ToastWhen: Always (startup, unlock, screen on) | Startup | Never
; ToastPosition: TopCenter | TopRight | TopLeft | BottomCenter | BottomRight | BottomLeft
; ToastAnimation: Slide | Fade | None
; Theme (settings window and tray menu): System | Light | Dark

)"

; ---- Runtime state ---------------------------------------------------------
SETTINGS_PATH := ""
CFG := {}                 ; active settings
DRAFT := {}               ; copy edited by the settings window
RT := {mode: "None", up: "", launchOn: false}   ; CFG precomputed for the hook
PAUSED := false
LOCKED := false           ; session locked (no toast on display-on then)
POWER_NOTIFY := 0
HELD := Map()             ; modifiers held down, tracked by the hook: name -> true
PRESS := Map()            ; keys whose down we handled: id -> {owner, t}
SWALLOW := Map()          ; keys whose key-up (and repeats) must be eaten: id -> tick
QUEUE := []               ; actions for RunQueue, in order
CAP := {active: false, target: "", mods: Map(), downs: Map(), result: 0}
HOOK := {proc: 0, h: 0}
NS := {checked: false, target: "", label: ""}   ; NitroSense auto-detection cache
UI := {gui: 0}
; Settings window layout, in logical pixels
SL := {W: 820, H: 630, side: 220, cx: 236, cw: 560, rx: 780, kvX: 426, btnX: 684}
; Update check: state "" | checking | latest | available | error
UPD := {state: "", latest: "", page: "", zip: "", sums: "", req: 0, manual: false, t0: 0
      , notified: "", trayItem: "Check for updates"}

Main()

; ============================================================================
; Startup / exit
; ============================================================================

Main() {
    global SETTINGS_PATH, CFG, POWER_NOTIFY
    args := ParseArgs()
    if args.restartPid {
        try ProcessWaitClose(args.restartPid, 5)    ; restart/update: let the old copy exit first
    } else if (other := OtherInstance()) {
        ; Already running (maybe with the tray icon hidden): open its settings instead
        DllCall("AllowSetForegroundWindow", "uint", 0xFFFFFFFF)
        DllCall("PostMessage", "ptr", other, "uint", INSTANCE_MSG, "ptr", 0, "ptr", 0)
        ExitApp
    }
    MarkInstance()
    OnMessage(INSTANCE_MSG, OnInstanceMsg)
    if FileExist(A_ScriptFullPath ".old")   ; the previous exe, left by an update
        try FileDelete(A_ScriptFullPath ".old")
    ProcessSetPriority("High")              ; costs nothing, keeps the hook snappy under load
    if (!A_IsCompiled && FileExist(IconPath()))
        TraySetIcon(IconPath())

    SETTINGS_PATH := SettingsPath()
    firstRun := !FileExist(SETTINGS_PATH)
    CFG := firstRun ? DefaultSettings() : LoadSettings(SETTINGS_PATH)
    if firstRun {
        try WriteSettings(SETTINGS_PATH, CFG)
    }
    ApplySettings()
    ApplyAppTheme(CFG.theme)                ; dark/light tray menu
    OnMessage(0x1A, OnSettingChange)        ; WM_SETTINGCHANGE: Windows switched light/dark

    HOOK.proc := CallbackCreate(KeyboardProc)
    if !HookInstall() {
        MsgBox("Couldn't install the keyboard hook, so keys can't be remapped.", APP.name, "Iconx")
        ExitApp(1)
    }
    OnExit(AppExit)

    BuildTray()
    if FileExist(APP.lnk)
        SetAutostart(true)                  ; recreate it: the app may have been moved

    ; Toast again on session unlock and when the display turns back on
    DllCall("LoadLibrary", "str", "wtsapi32", "ptr")     ; keep it loaded (see DEVELOPMENT.md)
    OnMessage(0x2B1, OnSessionChange)                    ; WM_WTSSESSION_CHANGE
    DllCall("wtsapi32\WTSRegisterSessionNotification", "ptr", A_ScriptHwnd, "uint", 0)
    displayGuid := Buffer(16)                            ; GUID_CONSOLE_DISPLAY_STATE
    DllCall("ole32\CLSIDFromString", "wstr", "{6FE69556-704A-47A0-8F24-C28D936FDA47}", "ptr", displayGuid)
    OnMessage(0x218, OnPower)                            ; WM_POWERBROADCAST
    POWER_NOTIFY := DllCall("RegisterPowerSettingNotification", "ptr", A_ScriptHwnd, "ptr", displayGuid, "uint", 0, "ptr")

    if firstRun {
        SetAutostart(true)                  ; on by default; the switch is right there to undo it
        UpdateTray()
        ShowSettings("keys")
        SetTimer(() => GlassToast("Welcome to " APP.short, "Choose what the key should do and click Save"), -700)
    } else if args.updated
        SetTimer(() => GlassToast("Updated to version " APP.version, "See what's new on the GitHub release page"), -2000)
    else if (CFG.toastWhen != "Never")
        SetTimer(StatusToast, -2000)        ; give the desktop time to paint
    ScheduleUpdateCheck()
}

; --restart <pid>: started by Restart or by an update; --updated: show "Updated"
ParseArgs() {
    out := {restartPid: 0, updated: false}
    for i, arg in A_Args {
        if (arg = "--restart" && i < A_Args.Length) {
            try out.restartPid := Integer(A_Args[i + 1])
        } else if (arg = "--updated")
            out.updated := true
    }
    return out
}

OtherInstance() {
    prev := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    found := 0
    for hwnd in WinGetList(INSTANCE_TITLE " ahk_class AutoHotkey")
        if (hwnd != A_ScriptHwnd) {
            found := hwnd
            break
        }
    DetectHiddenWindows(prev)
    return found
}

MarkInstance() {
    prev := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    WinSetTitle(INSTANCE_TITLE, A_ScriptHwnd)
    DetectHiddenWindows(prev)
}

OnInstanceMsg(*) {
    SetTimer(() => ShowSettings(), -1)
    return 1
}

RestartApp() {
    target := A_IsCompiled ? '"' A_ScriptFullPath '"' : '"' A_AhkPath '" "' A_ScriptFullPath '"'
    try Run(target " --restart " ProcessExist(), A_ScriptDir)
    catch {
        GlassToast("Couldn't restart", "Start the app again from its folder", "warn")
        return
    }
    ExitApp
}

AppExit(*) {
    ReleasePresses()
    RunQueue()                              ; send the key-up of a held remapped key
    if HOOK.h
        DllCall("UnhookWindowsHookEx", "ptr", HOOK.h), HOOK.h := 0
    DllCall("wtsapi32\WTSUnRegisterSessionNotification", "ptr", A_ScriptHwnd)
    if POWER_NOTIFY
        DllCall("UnregisterPowerSettingNotification", "ptr", POWER_NOTIFY)
}

IconPath() => FullPath(A_ScriptDir "\..\assets\icon.ico")

FullPath(path) {
    buf := Buffer(2048)
    n := DllCall("GetFullPathNameW", "str", path, "uint", 1024, "ptr", buf, "ptr", 0)
    return n ? StrGet(buf) : path
}

; ============================================================================
; Settings (settings.ini)
; ============================================================================

DefaultSettings() {
    return {sourceVK: 0xFF, sourceSC: 0x175, matchSC: true, mode: "NumLock"
          , targetMods: [], targetVK: 0, targetSC: 0
          , launchEnabled: true, launchMods: ["RCtrl"], launchVK: 0xFF, launchSC: 0x175
          , launchAnySide: false, launchPath: "auto"
          , toastWhen: "Always", toastPosition: "TopCenter", toastAnim: "Slide"
          , trayIcon: true, checkUpdates: true, theme: "System"}
}

CloneSettings(c) {
    copy := c.Clone()
    copy.targetMods := c.targetMods.Clone()
    copy.launchMods := c.launchMods.Clone()
    return copy
}

; Next to the exe if that folder is writable, otherwise %APPDATA%
SettingsPath() {
    beside := A_ScriptDir "\settings.ini", roaming := APP.dataDir "\settings.ini"
    if FileExist(beside)
        return beside
    if FileExist(roaming)
        return roaming
    if DirWritable(A_ScriptDir)
        return beside
    try DirCreate(APP.dataDir)
    return roaming
}

DirWritable(dir) {
    probe := dir "\~write-test-" A_TickCount ".tmp"
    try {
        FileAppend("", probe)
        FileDelete(probe)
        return true
    }
    return false
}

LoadSettings(path) {
    d := DefaultSettings()
    launchPath := IniStr(path, "Launcher", "LaunchPath", d.launchPath)
    if (launchPath = "")
        launchPath := "auto"
    return {sourceVK: IniHex(path, "Remap", "SourceVK", d.sourceVK)
          , sourceSC: IniHex(path, "Remap", "SourceSC", d.sourceSC)
          , matchSC: IniBool(path, "Remap", "MatchSC", d.matchSC)
          , mode: IniChoice(path, "Remap", "Mode", MODES, d.mode)
          , targetMods: ParseMods(IniStr(path, "Remap", "TargetMods", JoinMods(d.targetMods)))
          , targetVK: IniHex(path, "Remap", "TargetVK", d.targetVK)
          , targetSC: IniHex(path, "Remap", "TargetSC", d.targetSC)
          , launchEnabled: IniBool(path, "Launcher", "LaunchEnabled", d.launchEnabled)
          , launchMods: ParseMods(IniStr(path, "Launcher", "LaunchMods", JoinMods(d.launchMods)))
          , launchVK: IniHex(path, "Launcher", "LaunchVK", d.launchVK)
          , launchSC: IniHex(path, "Launcher", "LaunchSC", d.launchSC)
          , launchAnySide: IniBool(path, "Launcher", "LaunchAnySide", d.launchAnySide)
          , launchPath: launchPath
          , toastWhen: IniChoice(path, "General", "ToastWhen", TOAST_WHENS, d.toastWhen)
          , toastPosition: IniChoice(path, "General", "ToastPosition", TOAST_POSITIONS, d.toastPosition)
          , toastAnim: IniChoice(path, "General", "ToastAnimation", TOAST_ANIMS, d.toastAnim)
          , trayIcon: IniBool(path, "General", "TrayIcon", d.trayIcon)
          , checkUpdates: IniBool(path, "General", "CheckUpdates", d.checkUpdates)
          , theme: IniChoice(path, "General", "Theme", THEME_PREFS, d.theme)}
}

WriteSettings(path, c) {
    if !FileExist(path)
        FileAppend(INI_HEADER, path, "UTF-16 `n")   ; same encoding IniWrite uses, CRLF
    IniWrite(Hex(c.sourceVK), path, "Remap", "SourceVK")
    IniWrite(Hex(c.sourceSC), path, "Remap", "SourceSC")
    IniWrite(c.matchSC ? 1 : 0, path, "Remap", "MatchSC")
    IniWrite(c.mode, path, "Remap", "Mode")
    IniWrite(JoinMods(c.targetMods), path, "Remap", "TargetMods")
    IniWrite(Hex(c.targetVK), path, "Remap", "TargetVK")
    IniWrite(Hex(c.targetSC), path, "Remap", "TargetSC")
    IniWrite(c.launchEnabled ? 1 : 0, path, "Launcher", "LaunchEnabled")
    IniWrite(JoinMods(c.launchMods), path, "Launcher", "LaunchMods")
    IniWrite(Hex(c.launchVK), path, "Launcher", "LaunchVK")
    IniWrite(Hex(c.launchSC), path, "Launcher", "LaunchSC")
    IniWrite(c.launchAnySide ? 1 : 0, path, "Launcher", "LaunchAnySide")
    IniWrite(c.launchPath, path, "Launcher", "LaunchPath")
    IniWrite(c.toastWhen, path, "General", "ToastWhen")
    IniWrite(c.toastPosition, path, "General", "ToastPosition")
    IniWrite(c.toastAnim, path, "General", "ToastAnimation")
    IniWrite(c.trayIcon ? 1 : 0, path, "General", "TrayIcon")
    IniWrite(c.checkUpdates ? 1 : 0, path, "General", "CheckUpdates")
    IniWrite(c.theme, path, "General", "Theme")
}

; Missing key -> default. An empty value stays empty (e.g. "no modifiers").
IniStr(path, section, key, def) {
    v := IniRead(path, section, key, "<<unset>>")
    if (v == "<<unset>>")
        return def
    return Trim(RegExReplace(v, "\s+;.*$"))          ; allow "Key=value  ; comment"
}

IniHex(path, section, key, def) {
    v := IniStr(path, section, key, Hex(def))
    if (v = "")
        return 0
    try {
        n := Integer(v)
        if (n >= 0 && n <= 0xFFFF)
            return n
    }
    return def
}

IniBool(path, section, key, def) {
    v := IniStr(path, section, key, def ? "1" : "0")
    return !(v = "" || v = "0" || v = "false" || v = "no" || v = "off")
}

; One of a fixed list of words (case-insensitive), returned with the list's spelling
IniChoice(path, section, key, choices, def) {
    v := IniStr(path, section, key, def)
    for choice in choices
        if (v = choice)
            return choice
    return def
}

ParseMods(str) {
    found := Map()
    for part in StrSplit(str, [",", "+", " "]) {
        part := Trim(part)
        if (part = "")
            continue
        for name in MOD_ORDER
            if (part = name)
                found[name] := true
        if MOD_ALIAS.Has(StrLower(part))
            found[MOD_ALIAS[StrLower(part)]] := true
    }
    mods := []
    for name in MOD_ORDER
        if found.Has(name)
            mods.Push(name)
    return mods
}

JoinMods(mods) {
    out := ""
    for name in mods
        out .= (out = "" ? "" : ",") name
    return out
}

Hex(n) => Format("0x{:X}", n)

; Turns CFG into what the hook needs, so the hook does no string work
ApplySettings() {
    global RT
    ReleasePresses()
    c := CFG
    r := {mode: c.mode, srcVK: c.sourceVK, srcSC: c.matchSC ? c.sourceSC : 0
        , down: "", up: "", combo: ""
        , launchOn: c.launchEnabled && c.launchVK != 0
        , launchVK: c.launchVK, launchSC: c.launchSC
        , launchAny: c.launchAnySide, launchMods: Map()}
    if (!r.srcVK || (r.mode = "Key" && !c.targetVK))
        r.mode := "None"
    if (r.mode = "Key") {
        key := KeySpec(c.targetVK, c.targetSC)
        if !c.targetMods.Length {
            ; A real remap: down/up follow the source key, so holding repeats
            ; and Shift+source gives Shift+target
            r.down := "{Blind}{" key " down}", r.up := "{Blind}{" key " up}"
        } else {
            pre := "", post := ""
            for name in c.targetMods
                pre .= "{" name " down}", post := "{" name " up}" post
            r.combo := pre "{" key "}" post
        }
    }
    for name in c.launchMods
        r.launchMods[c.launchAnySide ? MOD_FAMILY[name] : name] := true
    RT := r
    GTCFG.position := c.toastPosition, GTCFG.animation := c.toastAnim
    A_IconHidden := !c.trayIcon
    UpdateTray()
}

; ============================================================================
; Keyboard hook
; ============================================================================

HookInstall() {
    ; Create the new hook before removing the old one. Also called after
    ; anything slow, because Windows silently drops a hook that times out.
    hNew := DllCall("SetWindowsHookEx", "int", 13, "ptr", HOOK.proc            ; WH_KEYBOARD_LL
                  , "ptr", DllCall("GetModuleHandle", "ptr", 0, "ptr"), "uint", 0, "ptr")
    if !hNew
        return false
    old := HOOK.h, HOOK.h := hNew
    if old
        DllCall("UnhookWindowsHookEx", "ptr", old)
    return true
}

CallNext(nCode, wParam, lParam) => DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam, "ptr")

KeyboardProc(nCode, wParam, lParam) {
    Critical
    if (nCode != 0)
        return CallNext(nCode, wParam, lParam)
    vk := NumGet(lParam, 0, "uint"), flags := NumGet(lParam, 8, "uint")
    sc := NumGet(lParam, 4, "uint") | ((flags & 1) << 8)          ; scan code + extended bit
    if (flags & 0x10)                                             ; injected: our own SendInput
        return CallNext(nCode, wParam, lParam)
    up := (flags & 0x80) != 0
    id := (vk << 16) | sc
    now := A_TickCount
    fake := (sc & 0x200) != 0                                     ; fake LCtrl sent with AltGr

    ; Key-up (and auto-repeat) of a key whose key-down we ate earlier
    if SWALLOW.Has(id) {
        if up {
            SWALLOW.Delete(id)
            return 1
        }
        if (now - SWALLOW[id] < REPEAT_MS) {
            SWALLOW[id] := now
            return 1
        }
        SWALLOW.Delete(id)                                        ; stale: the key-up was missed
    }

    ; Key detection for the settings window: before the rules, even if paused
    if CAP.active
        return CaptureKey(vk, sc, id, up, fake) ? 1 : CallNext(nCode, wParam, lParam)

    if (VK_MOD.Has(vk) && !fake) {
        name := VK_MOD[vk]
        if !up
            HELD[name] := true
        else if HELD.Has(name)
            HELD.Delete(name)
    }

    if PAUSED
        return CallNext(nCode, wParam, lParam)

    ; A key we are already handling: auto-repeat or release
    if PRESS.Has(id) {
        p := PRESS[id]
        if up {
            PRESS.Delete(id)
            return OnPressUp(p)
        }
        if (now - p.t < REPEAT_MS) {
            p.t := now
            return OnPressRepeat(p)
        }
        PRESS.Delete(id)                                          ; stale: treat as a new press
    }
    if up
        return CallNext(nCode, wParam, lParam)

    if (RT.launchOn && vk = RT.launchVK && (!RT.launchSC || sc = RT.launchSC) && LaunchModsHeld()) {
        PRESS[id] := {owner: "launch", t: now}
        Enqueue({do: "launch"})
        return 1
    }

    if (RT.mode != "None" && vk = RT.srcVK && (!RT.srcSC || sc = RT.srcSC)) {
        PRESS[id] := {owner: "remap", t: now}
        switch RT.mode {
            case "NumLock", "CapsLock", "ScrollLock":
                Enqueue({do: "toggle", key: RT.mode})
            case "Key":
                Enqueue({do: "send", keys: RT.combo != "" ? RT.combo : RT.down})
        }
        return 1                            ; Windows / vendor software never see the key
    }
    return CallNext(nCode, wParam, lParam)
}

OnPressRepeat(p) {
    ; Toggles ignore auto-repeat (holding the key toggles once). A key remap
    ; repeats like the real key; a shortcut is sent again on every repeat.
    if (p.owner = "remap" && RT.mode = "Key")
        Enqueue({do: "send", keys: RT.combo != "" ? RT.combo : RT.down})
    return 1
}

OnPressUp(p) {
    if (p.owner = "remap" && RT.mode = "Key" && RT.up != "")
        Enqueue({do: "send", keys: RT.up})
    return 1
}

LaunchModsHeld() {
    ; Drop modifiers whose key-up we missed (e.g. released while an
    ; elevated window had the focus)
    stale := []
    for name in HELD
        if !GetKeyState(name, "P")
            stale.Push(name)
    for name in stale
        HELD.Delete(name)
    return ModsMatch(HELD)
}

; The held modifiers must be exactly the required set (per family if "any side")
ModsMatch(down) {
    have := Map()
    for name in down
        have[RT.launchAny ? MOD_FAMILY[name] : name] := true
    if (have.Count != RT.launchMods.Count)
        return false
    for name in RT.launchMods
        if !have.Has(name)
            return false
    return true
}

; Forgets the keys being handled (settings changed, paused, exiting): sends
; the key-up of a held remapped key and eats the physical key-ups to come
ReleasePresses() {
    Critical
    now := A_TickCount
    for id, p in PRESS {
        if (p.owner = "remap" && RT.up != "")
            Enqueue({do: "send", keys: RT.up})
        SWALLOW[id] := now
    }
    PRESS.Clear()
}

; ---- Action queue (keeps order; nothing heavy runs inside the hook) --------

Enqueue(action) {
    QUEUE.Push(action)
    SetTimer(RunQueue, -1)
}

RunQueue() {
    while QUEUE.Length {
        act := QUEUE.RemoveAt(1)
        try {
            switch act.do {
                case "toggle": ToggleLock(act.key)
                case "send":   SendInput(act.keys)
                case "launch": LaunchApp()
            }
        }
    }
}

ToggleLock(key) {
    switch key {
        case "NumLock":    SetNumLockState(!GetKeyState("NumLock", "T"))
        case "CapsLock":   SetCapsLockState(!GetKeyState("CapsLock", "T"))
        case "ScrollLock": SetScrollLockState(!GetKeyState("ScrollLock", "T"))
    }
}

; ============================================================================
; Key / shortcut detection (runs inside the hook while the panel listens)
; ============================================================================

; Returns true to swallow the event
CaptureKey(vk, sc, id, up, fake) {
    isMod := VK_MOD.Has(vk) && !fake
    if up {
        if !CAP.downs.Has(id) {             ; pressed before listening started: let it go
            if (isMod && HELD.Has(VK_MOD[vk]))
                HELD.Delete(VK_MOD[vk])
            return false
        }
        CAP.downs.Delete(id)
        if isMod {                          ; a modifier alone: capture the modifier itself
            CAP.mods.Delete(VK_MOD[vk])
            CaptureFinish(vk, sc)
        }
        return true
    }
    if CAP.downs.Has(id)                    ; auto-repeat
        return true
    CAP.downs[id] := true
    if fake
        return true
    if isMod {
        CAP.mods[VK_MOD[vk]] := true
        return true
    }
    CaptureFinish(vk, sc)
    return true
}

CaptureFinish(vk, sc) {
    now := A_TickCount
    for id in CAP.downs                     ; keys still held: eat their key-ups later
        SWALLOW[id] := now
    keyMod := VK_MOD.Has(vk) ? VK_MOD[vk] : ""
    if (keyMod != "")
        vk := MOD_VK[keyMod]                ; generic Ctrl/Alt/Shift -> side-specific
    mods := []
    for name in MOD_ORDER
        if (CAP.mods.Has(name) && name != keyMod)
            mods.Push(name)
    CAP.result := {vk: vk, sc: sc, mods: mods}
    CAP.active := false
    SetTimer(CaptureDone, -1)               ; never touch the GUI from the hook
}

CaptureToggle(target) {
    Critical
    again := CAP.active && CAP.target = target
    CaptureCancel()
    if !again {
        CAP.target := target, CAP.mods := Map(), CAP.downs := Map(), CAP.result := 0
        CAP.active := true
        SetTimer(CaptureTimeout, -10000)
    }
    Critical "Off"
    RefreshSettings()
}

CaptureCancel() {
    Critical
    SetTimer(CaptureTimeout, 0)
    if !CAP.active
        return
    CAP.active := false
    now := A_TickCount
    for id in CAP.downs
        SWALLOW[id] := now
    CAP.downs := Map()
}

CaptureTimeout() {
    CaptureCancel()
    RefreshSettings()
}

CaptureDone() {
    SetTimer(CaptureTimeout, 0)
    r := CAP.result
    CAP.result := 0
    if (!r || !UI.gui)
        return
    switch CAP.target {
        case "source": DRAFT.sourceVK := r.vk, DRAFT.sourceSC := r.sc
        case "target": DRAFT.targetVK := r.vk, DRAFT.targetSC := r.sc, DRAFT.targetMods := r.mods
        case "launch": DRAFT.launchVK := r.vk, DRAFT.launchSC := r.sc, DRAFT.launchMods := r.mods
    }
    CommitDraft()
}

; ============================================================================
; Key names
; ============================================================================

KeySpec(vk, sc) => sc ? Format("vk{:02X}sc{:03X}", vk, sc) : Format("vk{:02X}", vk)

KeyLabel(vk, sc) {
    known := Format("{:X}:{:X}", vk, sc)
    if KNOWN_KEYS.Has(known)
        return KNOWN_KEYS[known]
    if VK_MOD.Has(vk)
        return MOD_LABEL[VK_MOD[vk]]
    name := GetKeyName(KeySpec(vk, sc))
    if (name != "") {
        if KEY_NAMES.Has(name)
            return KEY_NAMES[name]
        if (StrLen(name) = 1)
            return StrUpper(name)
        return RegExReplace(StrReplace(name, "_", " "), "(?<=[a-z])(?=[A-Z0-9])", " ")
    }
    return sc ? Format("Special key (SC {:X})", sc) : Format("Special key (VK {:X})", vk)
}

; ["Right Ctrl", "NitroSense key"]: the keys of a shortcut, in display order
ComboParts(mods, vk, sc, anySide := false) {
    parts := [], seen := Map()
    for name in mods {
        label := anySide ? MOD_FAMILY[name] : MOD_LABEL[name]
        if !seen.Has(label)
            parts.Push(label), seen[label] := true
    }
    parts.Push(KeyLabel(vk, sc))
    return parts
}

ComboLabel(mods, vk, sc, anySide := false) {
    out := ""
    for part in ComboParts(mods, vk, sc, anySide)
        out .= (out = "" ? "" : " + ") part
    return out
}

FieldText(vk, sc, mods := 0, anySide := false) {
    if !vk
        return "Not set"
    return ComboLabel(mods ? mods : [], vk, sc, anySide) " · " Format("VK {:X} SC {:X}", vk, sc)
}

Summary(c := 0) {
    if !c
        c := CFG
    src := c.sourceVK ? KeyLabel(c.sourceVK, c.sourceSC) : "No key"
    switch c.mode {
        case "NumLock":    return src " → Num Lock"
        case "CapsLock":   return src " → Caps Lock"
        case "ScrollLock": return src " → Scroll Lock"
        case "Key":        return src " → " (c.targetVK ? ComboLabel(c.targetMods, c.targetVK, c.targetSC) : "nothing")
        case "Disable":    return src " is disabled"
    }
    return c.launchEnabled ? "Remapping off, app shortcut on" : "Remapping is off"
}

; ============================================================================
; Opening NitroSense (or any app)
; ============================================================================

DetectNitroSense(force := false) {
    if (NS.checked && !force)
        return NS.target
    NS.checked := true, NS.target := "", NS.label := ""
    for dir in [A_ProgramFiles, EnvGet("ProgramW6432"), EnvGet("ProgramFiles(x86)")] {
        if (dir = "")
            continue
        for rel in ["\NitroSense\Prerequisites\NitroSenseLauncher.exe", "\NitroSense\NitroSense.exe"]
            if FileExist(dir rel) {
                NS.target := dir rel
                return NS.target
            }
    }
    ; Microsoft Store version: look it up in the Apps folder (can be slow)
    try {
        for item in ComObject("Shell.Application").NameSpace("shell:AppsFolder").Items()
            if InStr(item.Name, "NitroSense") {
                NS.target := "shell:AppsFolder\" item.Path, NS.label := item.Name " (Microsoft Store app)"
                break
            }
    }
    HookInstall()                           ; in case that took long enough to drop the hook
    return NS.target
}

TargetExists(t) => t != "" && (FileExist(t) || SubStr(t, 1, 6) = "shell:")

LaunchApp() {
    target := CFG.launchPath
    if (target = "auto") {
        target := DetectNitroSense()
        if !TargetExists(target)
            target := DetectNitroSense(true)    ; installed or moved since the last look
    }
    if !TargetExists(target) {
        GlassToast("App not found", "Choose it in Settings", "warn")
        return
    }
    try {
        if FileExist(target) {
            SplitPath(target, , &dir)
            Run('"' target '"', dir)
        } else
            Run(target)
    } catch {
        GlassToast("Couldn't open the app", "Check the app in Settings", "warn")
    }
    HookInstall()
}

; ============================================================================
; Toasts, session and display events
; ============================================================================

StatusToast() {
    if PAUSED
        GlassToast(APP.short " is paused", "Resume it from the tray icon", "info")
    else
        GlassToast(APP.short " is active", Summary())
}

OnSessionChange(wParam, lParam, msg, hwnd) {
    global LOCKED
    if (wParam = 0x8) {                     ; WTS_SESSION_UNLOCK
        LOCKED := false
        SetTimer(HookInstall, -500)
        if (CFG.toastWhen = "Always")
            SetTimer(StatusToast, -1200)    ; wait until the desktop is visible
    } else if (wParam = 0x7) {              ; WTS_SESSION_LOCK
        LOCKED := true
        SetTimer(GT_Free, -1)
    }
}

; Display turned off and on again without locking: no session event, so the
; console display state is watched instead (off = 0, on = 1, dimmed = 2)
OnPower(wParam, lParam, msg, hwnd) {
    static prev := -1                       ; the first notification is the current state
    if (wParam = 0x7 || wParam = 0x12) {    ; resumed from sleep
        SetTimer(HookInstall, -1000)
        return true
    }
    if (wParam != 0x8013)                   ; PBT_POWERSETTINGCHANGE
        return
    state := NumGet(lParam, 20, "uint")     ; POWERBROADCAST_SETTING: GUID(16) + length(4) + data
    if (state = 0)
        SetTimer(GT_Free, -1)
    else if (state = 1 && prev = 0 && !LOCKED) {
        SetTimer(HookInstall, -500)
        if (CFG.toastWhen = "Always")
            SetTimer(StatusToast, -1500)
    }
    prev := state
    return true
}

; ============================================================================
; Tray menu
; ============================================================================

BuildTray() {
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Settings…", (*) => ShowSettings())
    tray.Add("Pause remapping", (*) => TogglePause())
    tray.Add("Start with Windows", (*) => ToggleAutostart())
    tray.Add()
    tray.Add(UPD.trayItem, (*) => UpdateAction())
    tray.Add("Open settings folder", (*) => OpenSettingsFolder())
    tray.Add("About / GitHub", (*) => ShowAbout())
    tray.Add()
    tray.Add("Restart", (*) => RestartApp())
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Settings…"
    tray.ClickCount := 2
    OnMessage(0x404, OnTrayNotify)          ; AHK_NOTIFYICON
    UpdateTray()
}

; Shows the tray menu Per-Monitor DPI aware: with the app's system-DPI
; awareness, Windows put it in the wrong place and at the wrong size on a
; monitor whose scale differs from the main one.
OnTrayNotify(wParam, lParam, msg, hwnd) {
    event := lParam & 0xFFFF
    if (event != 0x205 && event != 0x7B)    ; WM_RBUTTONUP, WM_CONTEXTMENU
        return
    ShowMenuAtCursor(A_TrayMenu)
    return 1
}

ShowMenuAtCursor(m) {
    old := PMv2()
    pt := Buffer(8)
    DllCall("GetCursorPos", "ptr", pt)
    CoordMode("Menu", "Screen")
    m.Show(NumGet(pt, 0, "int"), NumGet(pt, 4, "int"))
    PMv2(old)
}

; Switches this thread to Per-Monitor v2 DPI awareness and returns the old
; context; PMv2(old) restores it.
PMv2(old := 0) => DllCall("SetThreadDpiAwarenessContext", "ptr", old ? old : -4, "ptr")

UpdateTray() {
    try {
        PAUSED ? A_TrayMenu.Check("Pause remapping") : A_TrayMenu.Uncheck("Pause remapping")
        FileExist(APP.lnk) ? A_TrayMenu.Check("Start with Windows") : A_TrayMenu.Uncheck("Start with Windows")
        item := UPD.state = "available" ? "Install update " UPD.latest "…" : "Check for updates"
        if (item != UPD.trayItem) {
            A_TrayMenu.Rename(UPD.trayItem, item)
            UPD.trayItem := item
        }
    }
    A_IconTip := SubStr(APP.name (PAUSED ? " (paused)" : "") "`n" Summary(), 1, 127)
}

TogglePause() => SetPaused(!PAUSED)

SetPaused(state, toast := true) {
    global PAUSED
    ReleasePresses()
    PAUSED := state ? 1 : 0
    UpdateTray()
    RefreshSettings()                       ; if the window is open
    if !toast
        return
    if PAUSED
        GlassToast("Remapping paused", "Keys work as usual until you resume", "info", 2500)
    else
        GlassToast("Remapping resumed", Summary(), "ok", 2500)
}

ToggleAutostart() {
    on := !FileExist(APP.lnk)
    if !SetAutostart(on)
        return
    UpdateTray()
    RefreshSettings()
}

; Shortcut in the Startup folder. From source it must run AutoHotkey64.exe
; with the script as argument: a shortcut to the .ahk doesn't start at logon.
SetAutostart(on) {
    try {
        if !on {
            if FileExist(APP.lnk)
                FileDelete(APP.lnk)
        } else if A_IsCompiled
            FileCreateShortcut(A_ScriptFullPath, APP.lnk, A_ScriptDir, , APP.name)
        else
            FileCreateShortcut(A_AhkPath, APP.lnk, A_ScriptDir, '"' A_ScriptFullPath '"', APP.name
                             , FileExist(IconPath()) ? IconPath() : A_AhkPath)
        return true
    } catch as e {
        GlassToast("Couldn't change Start with Windows", e.Message, "warn")
        return false
    }
}

OpenSettingsFolder() {
    if FileExist(SETTINGS_PATH)
        Run('explorer.exe /select,"' SETTINGS_PATH '"')
    else {
        SplitPath(SETTINGS_PATH, , &dir)
        Run(dir)
    }
}

; ============================================================================
; Updates (GitHub releases)
; ============================================================================
; The check is asynchronous (WinHttp + a polling timer): a blocking request
; would stall the keyboard hook. Installing replaces the exe in place: it's
; downloaded, verified against the release's SHA256SUMS.txt, the running exe
; is renamed to .old (Windows allows that) and the new one is started.

ScheduleUpdateCheck() {
    SetTimer(AutoCheckUpdates, CFG.checkUpdates ? -60000 : 0)     ; not during logon
}

AutoCheckUpdates() {
    if !CFG.checkUpdates
        return
    CheckUpdates(false)
    SetTimer(AutoCheckUpdates, -24 * 3600 * 1000)                 ; then once a day
}

UpdateAction() {
    if (UPD.state = "available")
        InstallUpdate()
    else
        CheckUpdates(true)
}

CheckUpdates(manual := false) {
    if (UPD.state = "checking")
        return
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", APP.api, true)
        req.SetRequestHeader("User-Agent", "Win11KeyRemapper/" APP.version)
        req.SetRequestHeader("Accept", "application/vnd.github+json")
        req.Send()
    } catch {
        UpdateDone("error", manual)
        return
    }
    UPD.req := req, UPD.manual := manual, UPD.t0 := A_TickCount, UPD.state := "checking"
    RefreshSettings()
    SetTimer(PollUpdates, 250)
}

PollUpdates() {
    req := UPD.req, done := false, failed := false
    try done := req.WaitForResponse(0)      ; COM true is -1
    catch
        failed := true
    if (!done && !failed && A_TickCount - UPD.t0 < 20000)
        return
    SetTimer(PollUpdates, 0)
    UPD.req := 0
    status := 0, text := ""
    if (done && !failed)
        try status := req.Status, text := req.ResponseText
    if (status = 404)                       ; no release published yet
        return UpdateDone("latest", UPD.manual)
    rel := status = 200 ? ParseRelease(text) : {tag: ""}
    if (rel.tag = "")
        return UpdateDone("error", UPD.manual)
    if !VersionNewer(rel.tag, APP.version)
        return UpdateDone("latest", UPD.manual)
    UPD.latest := rel.tag, UPD.page := rel.page, UPD.zip := rel.zip, UPD.sums := rel.sums
    UpdateDone("available", UPD.manual)
}

UpdateDone(state, manual) {
    UPD.state := state
    UpdateTray()
    RefreshSettings()
    if (state = "available") {
        if (manual || (CFG.toastWhen != "Never" && UPD.notified != UPD.latest))
            GlassToast("Update available: " UPD.latest, "Install it from Settings or the tray menu", "update", 7000)
        UPD.notified := UPD.latest
    } else if (manual && state = "latest")
        GlassToast("You're up to date", APP.short " " APP.version, "ok", 3000)
    else if (manual && state = "error")
        GlassToast("Couldn't check for updates", "Check your connection and try again", "warn")
}

; Minimal reading of GitHub's "latest release" JSON
ParseRelease(json) {
    rel := {tag: "", page: "", zip: "", sums: ""}
    if RegExMatch(json, '"tag_name"\s*:\s*"([^"]+)"', &m)
        rel.tag := m[1]
    if RegExMatch(json, '"html_url"\s*:\s*"([^"]+/releases/tag/[^"]+)"', &m)
        rel.page := m[1]
    if RegExMatch(json, '"browser_download_url"\s*:\s*"([^"]+/Win11KeyRemapper-v[^"/]+\.zip)"', &m)
        rel.zip := m[1]
    if RegExMatch(json, '"browser_download_url"\s*:\s*"([^"]+/SHA256SUMS\.txt)"', &m)
        rel.sums := m[1]
    return rel
}

VersionNewer(tag, current) {
    if !RegExMatch(tag, "(\d+)\.(\d+)\.(\d+)", &mNew) || !RegExMatch(current, "(\d+)\.(\d+)\.(\d+)", &mCur)
        return false
    loop 3 {
        a := Integer(mNew[A_Index]), b := Integer(mCur[A_Index])
        if (a != b)
            return a > b
    }
    return false
}

InstallUpdate() {
    if (UPD.state != "available")
        return
    page := UPD.page != "" ? UPD.page : APP.repo "/releases/latest"
    if (!A_IsCompiled || UPD.zip = "" || UPD.sums = "" || !DirWritable(A_ScriptDir)) {
        Run(page)                           ; from source or in a protected folder: manual download
        return
    }
    if (MsgBox("Install " APP.short " " UPD.latest "?`n`nIt will be downloaded from GitHub, checked, installed in place of this version, and the app will restart.", APP.name, "OKCancel Iconi") != "OK")
        return
    dir := A_Temp "\Win11KeyRemapper-update"
    SplitPath(UPD.zip, &zipName)
    try {
        if DirExist(dir)
            DirDelete(dir, true)
        DirCreate(dir "\files")
        Download(UPD.zip, dir "\" zipName)
        Download(UPD.sums, dir "\SHA256SUMS.txt")
    } catch as e {
        HookInstall()
        return UpdateFailed("The download failed: " e.Message, page)
    }
    HookInstall()                           ; the download kept this thread busy for a moment
    sums := ReadSums(dir "\SHA256SUMS.txt")
    exeName := "Win11KeyRemapper.exe"
    if (!sums.Has(zipName) || !sums.Has(exeName) || Sha256File(dir "\" zipName) != sums[zipName])
        return UpdateFailed("The downloaded file doesn't match its checksum.", page)
    shell := ComObject("Shell.Application")
    shell.NameSpace(dir "\files").CopyHere(shell.NameSpace(dir "\" zipName).Items(), 4 | 16 | 1024)
    newExe := dir "\files\" exeName
    loop 50 {                               ; unzipping may finish in the background
        if (Sha256File(newExe) = sums[exeName])
            break
        Sleep(100)
    }
    if (Sha256File(newExe) != sums[exeName])
        return UpdateFailed("The update couldn't be unpacked.", page)
    old := A_ScriptFullPath ".old"
    try {
        if FileExist(old)
            FileDelete(old)
        FileMove(A_ScriptFullPath, old)     ; renaming a running exe is allowed
        try FileCopy(newExe, A_ScriptFullPath)
        catch as e {
            FileMove(old, A_ScriptFullPath)
            throw e
        }
    } catch as e
        return UpdateFailed("The app couldn't be replaced: " e.Message, page)
    Run('"' A_ScriptFullPath '" --restart ' ProcessExist() " --updated", A_ScriptDir)
    ExitApp
}

UpdateFailed(msg, page) {
    MsgBox(msg "`n`nThe release page will open so you can download it manually.", APP.name, "Icon!")
    try Run(page)
}

ReadSums(path) {                        ; "hash  file" lines -> Map(file, hash)
    sums := Map()
    try {
        for line in StrSplit(FileRead(path), "`n", "`r ")
            if RegExMatch(line, "i)^([0-9a-f]{64})\s+\*?(\S.*)$", &m)
                sums[Trim(m[2])] := StrLower(m[1])
    }
    return sums
}

Sha256File(path) {                      ; lowercase hex, "" if unreadable
    static lib := DllCall("LoadLibrary", "str", "bcrypt", "ptr")    ; the handle spans calls
    try data := FileRead(path, "RAW")
    catch
        return ""
    alg := 0, hash := Buffer(32)
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &alg, "wstr", "SHA256", "ptr", 0, "uint", 0)
    DllCall("bcrypt\BCryptHash", "ptr", alg, "ptr", 0, "uint", 0, "ptr", data, "uint", data.Size, "ptr", hash, "uint", 32)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", alg, "uint", 0)
    out := ""
    loop 32
        out .= Format("{:02x}", NumGet(hash, A_Index - 1, "uchar"))
    return out
}

ShowAbout() {
    text := APP.name " " APP.version "`n(NitroSense Key Remapper)`n`n"
          . "Remaps the Acer NitroSense key, or any other key, on Windows.`n"
          . "Free and open source (MIT License).`n`n"
          . "Open the GitHub page?"
    if (MsgBox(text, "About " APP.short, "YesNo Iconi") = "Yes")
        Run(APP.repo)
}

; ============================================================================
; Settings window
; ============================================================================
; Windows 11 style: a sidebar with sections, each section a column of
; setting cards (title, description, control on the right). Every change is
; applied and saved at once; if something is missing (e.g. the key to send),
; the row says so and the previous setting stays active.
;
; Standard Win32 controls can't draw rounded cards, keycaps, switches or the
; sidebar, so those are drawn with GDI+ into bitmaps: the cards are painted
; on WM_ERASEBKGND, everything else is a Picture control.
;
; The window is Per-Monitor DPI aware (v2) while the rest of the app is
; system-aware: it's created in a PMv2 thread context with -DPIScale,
; positions and font sizes are scaled by hand (Px, FontPts) and every
; control is remembered in UI.items, so on WM_DPICHANGED everything is laid
; out again for the new monitor and stays sharp.

ShowSettings(page := "") {
    global DRAFT
    if UI.gui {
        if (page != "")
            ShowPage(page)
        UI.gui.Show()
        return
    }
    DRAFT := CloneSettings(CFG)
    BuildSettings(page != "" ? page : "keys")
    if !NS.checked
        SetTimer(DetectForApp, -150)        ; after the window is on screen
}

BuildSettings(page, posX := "", posY := "") {
    static hooked := false
    if !hooked {
        OnMessage(0x14, OnSettingsErase)            ; WM_ERASEBKGND: paint the cards
        OnMessage(0x135, OnSettingsCtlColorBtn)     ; WM_CTLCOLORBTN: button corners
        OnMessage(0x134, OnSettingsCtlColorList)    ; WM_CTLCOLORLISTBOX: dark drop-down lists
        OnMessage(0x2E0, OnSettingsDpiChanged)      ; WM_DPICHANGED: moved to another monitor
        OnMessage(0x200, OnSettingsMouseMove)       ; WM_MOUSEMOVE: ⓘ tooltips
        OnMessage(0x138, OnSettingsCtlColorStatic)  ; WM_CTLCOLORSTATIC: icons on cards
        hooked := true
    }
    old := PMv2()
    if (posX = "") {                        ; center on the monitor under the mouse
        mon := GT_MouseMonitor()
        MonitorGetWorkArea(mon, &wl, &wt, &wr, &wb)
        UI.dpi := GT_MonitorDpi(mon)
    } else
        UI.dpi := DpiAt(posX, posY)
    UI.k := UI.dpi / 96
    UI.themeName := ThemeName(DRAFT.theme)
    th := UI.th := THEMES[UI.themeName]
    UI.tok := GdipStart()
    UI.page := page, UI.problem := "", UI.problemWhere := "", UI.tipFor := 0, UI.bgBmp := 0
    UI.items := [], UI.itemOf := Map(), UI.icons := [], UI.groups := Map(), UI.nav := Map()
    UI.keyText := Map(), UI.tg := Map(), UI.tgState := Map(), UI.cardBtns := Map(), UI.infoTips := Map(), UI.cardStatics := Map()
    UI.kvW := SL.btnX - 10 - SL.kvX
    UI.brushWin := DllCall("CreateSolidBrush", "uint", Bgr(th.win), "ptr")
    UI.brushCard := DllCall("CreateSolidBrush", "uint", Bgr(th.card), "ptr")
    for p in PAGES
        UI.groups[p[1]] := []

    g := Gui("-MinimizeBox -MaximizeBox -DPIScale", APP.name)
    UI.gui := g
    g.BackColor := Hex6(th.win)
    g.MarginX := 0, g.MarginY := 0
    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    ; Sidebar: app name, status, sections
    AddIcon("", 20, 16, 28)
    Place("Text", "", 56, 14, 150, 22, "0x80 Background" Hex6(th.win), APP.short, 12, "w600", th.text)
    UI.status := Place("Text", "", 56, 36, 150, 16, "0x80 Background" Hex6(th.win), "", 8.5, "w400", th.ok)
    for i, p in PAGES {
        pic := Place("Picture", "", 8, 72 + (i - 1) * 40, SL.side - 16, 36)
        pic.OnEvent("Click", ShowPage.Bind(p[1]))
        UI.nav[p[1]] := pic
    }

    ; Content header: section title and the ⋯ menu
    UI.title := Place("Text", "", SL.cx, 14, 400, 38, "0x80 Background" Hex6(th.win), "", 20, "w600", th.text)
    UI.more := NewButton("", SL.W - 24 - 44, 18, 44, Chr(0xE712), false, 11, "Segoe MDL2 Assets|Segoe Fluent Icons")
    UI.more.OnEvent("Click", ShowMoreMenu)

    BuildGeneralPage()
    BuildKeysPage()
    BuildNotificationsPage()
    BuildUpdatesPage()
    BuildAdvancedPage()
    BuildAboutPage()

    ThemeTitleBar(g.Hwnd)
    RefreshSettings()
    ShowPage(page)
    w := Px(SL.W), h := Px(SL.H)
    if (posX = "")
        posX := wl + (wr - wl - w) // 2, posY := wt + Max(0, (wb - wt - h) // 2 - Px(20))
    showOpts := "x" posX " y" posY " w" w " h" h
    g.Show(showOpts)
    PMv2(old)
}

; ---- Pages -----------------------------------------------------------------

BuildGeneralPage() {
    grp := Group("general", 70)
    y := Row(grp, 64)
    RowText("general", y, 64, "Remapping", "Off: all keys work as usual until you turn it back on.", 470)
    NewSwitch("remapping", "general", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    RowText("general", y, 64, "Start with Windows", "Start the app when you sign in.", 470)
    NewSwitch("autostart", "general", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    RowText("general", y, 64, "Show the icon in the tray", "If it's hidden, open the app again to see this window.", 470)
    NewSwitch("trayIcon", "general", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    RowText("general", y, 64, "Theme", "Colors of this window and of the tray menu.", 330)
    UI.theme := NewList("general", SL.rx - 160, y + 17, 160, THEME_PREFS, OnThemeChange)
}

BuildKeysPage() {
    th := UI.th, x := SL.cx + 16
    grp := Group("keys", 70, "Remap a key")
    y := Row(grp, 64)
    r := RowText("keys", y, 64, "Key", "", SL.kvX - 10 - x)
    UI.srcDesc := r.desc
    UI.srcKeys := NewKeyView("source", "keys", SL.kvX, y + 15)
    UI.srcBtn := NewButton("keys", SL.btnX, y + 17, 96, "Change…")
    UI.srcBtn.OnEvent("Click", (*) => CaptureToggle("source"))
    y := Row(grp, 92)
    RowText("keys", y, 92, "Action", "", SL.kvX - 10 - x, "", 17)
    UI.mode := NewList("keys", SL.kvX, y + 13, SL.rx - SL.kvX, MODE_LABELS, OnModeChange)
    UI.actionInfo := Place("Text", "keys", x, y + 54, SL.rx - x, 20, "0x80 Background" Hex6(th.card), "", 9, "w400", th.sub)
    y := Row(grp, 64)
    r := RowText("keys", y, 64, "Sends", "What to press instead.", SL.kvX - 10 - x)
    UI.targetTitle := r.title, UI.targetDesc := r.desc
    UI.targetKeys := NewKeyView("target", "keys", SL.kvX, y + 15)
    UI.targetBtn := NewButton("keys", SL.btnX, y + 17, 96, "Change…")
    UI.targetBtn.OnEvent("Click", (*) => CaptureToggle("target"))

    grp := Group("keys", grp.y + grp.h + 16, "NitroSense shortcut")
    y := Row(grp, 64)
    RowText("keys", y, 64, "Open an app with a shortcut", "By default, Right Ctrl + NitroSense key opens NitroSense.", SL.rx - 50 - x)
    NewSwitch("launchEnabled", "keys", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    r := RowText("keys", y, 64, "Shortcut", "", SL.kvX - 10 - x)
    UI.launchTitle := r.title, UI.launchDesc := r.desc
    UI.launchKeys := NewKeyView("launch", "keys", SL.kvX, y + 15)
    UI.launchBtn := NewButton("keys", SL.btnX, y + 17, 96, "Change…")
    UI.launchBtn.OnEvent("Click", (*) => CaptureToggle("launch"))
    y := Row(grp, 52)
    r := RowText("keys", y, 52, "Distinguish left and right modifiers", "", SL.rx - 80 - x
               , "On: only the exact keys of the shortcut work (for example Right Ctrl).`n"
               . "Off: the same key on either side works too (Left or Right Ctrl).")
    UI.sidesTitle := r.title
    NewSwitch("distinguish", "keys", SL.rx - 40, y + 16)
    y := Row(grp, 64)
    r := RowText("keys", y, 64, "App to open", "", SL.btnX - 82 - x)
    UI.appTitle := r.title, UI.appStatus := r.desc
    UI.auto := NewButton("keys", SL.btnX - 72, y + 17, 64, "Auto")
    UI.browse := NewButton("keys", SL.btnX, y + 17, 96, "Browse…")
    UI.auto.OnEvent("Click", AutoApp)
    UI.browse.OnEvent("Click", BrowseApp)
}

BuildNotificationsPage() {
    grp := Group("notifications", 70)
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Show notifications", "Always: at startup, after unlocking and when the screen turns on.", 290)
    UI.toastWhen := NewList("notifications", SL.rx - 220, y + 17, 220, TOAST_WHEN_LABELS
                          , (ctl, *) => (DRAFT.toastWhen := TOAST_WHENS[ctl.Value], CommitDraft()))
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Position", "Where they appear on the screen.", 270)
    UI.toastPos := NewList("notifications", SL.rx - 220, y + 17, 220, TOAST_POSITION_LABELS
                         , (ctl, *) => (DRAFT.toastPosition := TOAST_POSITIONS[ctl.Value], CommitDraft()))
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Animation", "How they appear and leave.", 270)
    UI.toastAnim := NewList("notifications", SL.rx - 220, y + 17, 220, TOAST_ANIM_LABELS
                          , (ctl, *) => (DRAFT.toastAnim := TOAST_ANIMS[ctl.Value], CommitDraft()))
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Preview", "Show a notification with these settings.", 330)
    NewButton("notifications", SL.rx - 160, y + 17, 160, "Show a test").OnEvent("Click", PreviewToast)
}

BuildUpdatesPage() {
    grp := Group("updates", 70)
    y := Row(grp, 64)
    RowText("updates", y, 64, "Check for updates automatically", "Once a day, from GitHub. Nothing about you is sent.", 470)
    NewSwitch("checkUpdates", "updates", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    r := RowText("updates", y, 64, "Version " APP.version, "", 340)
    UI.updText := r.desc
    UI.updBtn := NewButton("updates", SL.rx - 170, y + 17, 170, "Check now")
    UI.updBtn.OnEvent("Click", (*) => UpdateAction())
    y := Row(grp, 64)
    RowText("updates", y, 64, "Release notes", "What changed in each version.", 400)
    NewButton("updates", SL.rx - 96, y + 17, 96, "Open").OnEvent("Click", (*) => Run(APP.repo "/releases"))
}

BuildAdvancedPage() {
    grp := Group("advanced", 70)
    y := Row(grp, 64)
    RowText("advanced", y, 64, "Exact key match", "Recommended for vendor keys like NitroSense.", 400
          , "Also compares the scan code, not only the key code. Needed when several`n"
          . "keys share a code, like the NitroSense key and Win Lock (Fn+Win) on Acer`n"
          . "laptops. Turn it off only if your key changes its scan code.")
    NewSwitch("matchSC", "advanced", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    r := RowText("advanced", y, 64, "Settings file", "", SL.rx - 140 - SL.cx - 16)
    UI.settingsPath := r.desc
    NewButton("advanced", SL.rx - 130, y + 17, 130, "Open folder").OnEvent("Click", (*) => OpenSettingsFolder())
    y := Row(grp, 64)
    RowText("advanced", y, 64, "Reset all settings", "Puts every option back to its default value.", 400)
    NewButton("advanced", SL.rx - 110, y + 17, 110, "Reset…").OnEvent("Click", ResetSettings)
    y := Row(grp, 64)
    RowText("advanced", y, 64, "Restart the app", "For example after editing settings.ini by hand.", 400)
    NewButton("advanced", SL.rx - 110, y + 17, 110, "Restart").OnEvent("Click", (*) => RestartApp())
}

BuildAboutPage() {
    th := UI.th, x := SL.cx + 16
    grp := Group("about", 70)
    Row(grp, 84)
    AddIcon("about", x, 88, 48)
    Place("Text", "about", x + 64, 84, 400, 26, "0x80 Background" Hex6(th.card), APP.name, 14, "w600", th.text)
    Place("Text", "about", x + 64, 112, 460, 34, "0x80 Background" Hex6(th.card)
        , "Version " APP.version " · MIT License · Remaps the NitroSense key, or any other key.", 9, "w400", th.sub)

    grp := Group("about", grp.y + grp.h + 16, "Help and feedback")
    for link in LINKS {
        y := Row(grp, 40)
        url := APP.repo link[2]
        t := Place("Text", "about", x, y + 10, 400, 20, "0x80 Background" Hex6(th.card), link[1], 10.5, "w400", th.text)
        icon := Place("Text", "about", SL.rx - 24, y + 11, 20, 18, "Background" Hex6(th.card), Chr(0xE8A7), 10, "w400", th.sub
                    , "Segoe MDL2 Assets|Segoe Fluent Icons")
        for ctl in [t, icon]
            ctl.OnEvent("Click", OpenUrl.Bind(url))
    }

    grp := Group("about", grp.y + grp.h + 16, "Frequently asked questions")
    Row(grp, SL.H - 20 - grp.y)
    faq := Place("Edit", "about", x - 4, grp.y + 8, SL.cw - 24, SL.H - 36 - grp.y
               , "ReadOnly Multi VScroll -E0x200 -TabStop Background" Hex6(th.card), FAQ_TEXT, 9.5, "w400", th.text)
    ThemeCtl(faq)
}

OpenUrl(url, *) => Run(url)

; ---- Building blocks ---------------------------------------------------------

Px(n) => Round(n * UI.k)
FontPts(pts) => Round(pts * UI.dpi / A_ScreenDPI, 2)   ; AutoHotkey sizes fonts for the main monitor

DpiAt(x, y) {
    hMon := DllCall("MonitorFromPoint", "int64", (x & 0xFFFFFFFF) | (y << 32), "uint", 2, "ptr")
    dx := 0, dy := 0
    try {
        if DllCall("shcore\GetDpiForMonitor", "ptr", hMon, "int", 0, "uint*", &dx, "uint*", &dy) = 0 && dx
            return dx
    }
    return A_ScreenDPI
}

; Adds a control at logical coordinates and remembers it for DPI changes.
; page "" = always visible (sidebar, header).
Place(type, page, x, y, w, h, opts := "", text := "", pts := 10, style := "w400", color := -1, fontName := "Segoe UI") {
    item := {x: x, y: y, w: w, h: h, pts: pts, style: style, color: color, fontName: fontName, page: page}
    ItemFont(UI.gui, item)
    pos := "x" Px(x) " y" Px(y) " w" Px(w) (h != "" ? " h" Px(h) : "")
    ctl := UI.gui.Add(type, pos " " opts, text)
    item.ctl := ctl
    UI.items.Push(item)
    UI.itemOf[ctl.Hwnd] := item
    return ctl
}

ItemFont(target, item) {                ; target: the Gui (before adding) or the control
    opts := "s" FontPts(item.pts) " " item.style (item.color >= 0 ? " c" Hex6(item.color) : "")
    for name in StrSplit(item.fontName, "|")
        target.SetFont(opts, name)      ; the last font that exists wins
}

AddIcon(page, x, y, size) {
    has := A_IsCompiled || FileExist(IconPath())       ; from source, assets\ may be missing
    ctl := Place("Picture", page, x, y, size, size, A_IsCompiled ? "Icon1" : "", has ? (A_IsCompiled ? A_ScriptFullPath : IconPath()) : "")
    if !has
        return
    UI.icons.Push({ctl: ctl, size: size})
    if (page != "")
        UI.cardStatics[ctl.Hwnd] := true        ; drawn on a card, not on the window color
}

IconSpec(size) => (A_IsCompiled ? "*icon1 " : "") "*w" Px(size) " *h" Px(size) " " (A_IsCompiled ? A_ScriptFullPath : IconPath())

; A card group; the rows are added with Row(). Optional section title above.
Group(page, y, title := "") {
    if (title != "")
        Place("Text", page, SL.cx + 2, y, 400, 22, "0x80 Background" Hex6(UI.th.win), title, 10.5, "w600", UI.th.text), y += 28
    grp := {x: SL.cx, y: y, w: SL.cw, h: 0, dividers: []}
    UI.groups[page].Push(grp)
    return grp
}

Row(grp, h) {
    if grp.h
        grp.dividers.Push(grp.h)
    y := grp.y + grp.h
    grp.h += h
    return y
}

; Title and description on the left of a row; optional ⓘ with a tooltip
RowText(page, y, h, title, desc, textW, info := "", titleY := "") {
    th := UI.th, x := SL.cx + 16, bg := " Background" Hex6(th.card)
    if (titleY = "")
        titleY := desc = "" && h <= 52 ? (h - 20) // 2 : 12
    out := {desc: 0}
    out.title := Place("Text", page, x, y + titleY, textW, 20, "0x80" bg, title, 10.5, "w400", th.text)
    if (desc != "" || titleY = 12)
        out.desc := Place("Text", page, x, y + 34, textW, 18, "0x4080" bg, desc, 9, "w400", th.sub)
    if (info != "") {                       ; the ⓘ goes right after the title
        tw := TextWidth(out.title, title) + 2
        UI.itemOf[out.title.Hwnd].w := tw
        out.title.Move(, , Px(tw))
        icon := Place("Text", page, x + tw + 6, y + titleY + 2, 18, 18, bg, Chr(0xE946), 10, "w400", th.sub
                    , "Segoe MDL2 Assets|Segoe Fluent Icons")
        icon.OnEvent("Click", (ctl, *) => ShowInfoTip(ctl.Hwnd))
        UI.infoTips[icon.Hwnd] := info
    }
    return out
}

TextWidth(ctl, text) {                  ; in logical pixels, with the control's font
    hdc := DllCall("GetDC", "ptr", ctl.Hwnd, "ptr")
    font := SendMessage(0x31, 0, 0, ctl)                    ; WM_GETFONT
    old := DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr")
    sz := Buffer(8, 0)
    DllCall("GetTextExtentPoint32", "ptr", hdc, "str", text, "int", StrLen(text), "ptr", sz)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("ReleaseDC", "ptr", ctl.Hwnd, "ptr", hdc)
    return Ceil(NumGet(sz, 0, "int") / UI.k)
}

NewButton(page, x, y, w, text, onCard := true, pts := 10, fontName := "Segoe UI") {
    btn := Place("Button", page, x, y, w, 30, "", text, pts, "w400", -1, fontName)
    ThemeCtl(btn)
    if onCard
        UI.cardBtns[btn.Hwnd] := true
    return btn
}

NewList(page, x, y, w, items, onChange) {
    ddl := Place("DropDownList", page, x, y, w, "", "AltSubmit", items, 10, "w400", UI.th.text)
    ThemeCtl(ddl, "combo")
    ddl.OnEvent("Change", onChange)
    return ddl
}

; The keys of a shortcut drawn as keycaps; click = same as "Change…"
NewKeyView(name, page, x, y) {
    pic := Place("Picture", page, x, y, UI.kvW, 34)
    pic.OnEvent("Click", (*) => CaptureToggle(name))
    return pic
}

; On/off switch (a picture: clicking it flips the setting)
NewSwitch(name, page, x, y) {
    pic := Place("Picture", page, x, y, 40, 20)
    pic.OnEvent("Click", (*) => FlipSwitch(name))
    pic.OnEvent("DoubleClick", (*) => FlipSwitch(name))     ; fast second click
    UI.tg[name] := pic
    return pic
}

ShowPage(name, *) {
    if !UI.gui
        return
    old := PMv2()
    UI.page := name
    for item in UI.items
        if (item.page != "")
            item.ctl.Visible := item.page = name
    for p in PAGES
        if (p[1] = name)
            UI.title.Value := p[2]
    ToolTip()
    RenderChrome()
    DllCall("InvalidateRect", "ptr", UI.gui.Hwnd, "ptr", 0, "int", 1)
    PMv2(old)
}

; Background (cards of the current page) and sidebar items
RenderChrome() {
    if UI.bgBmp
        DllCall("DeleteObject", "ptr", UI.bgBmp)
    UI.bgW := Px(SL.W), UI.bgH := Px(SL.H)
    UI.bgBmp := RenderBackground(SL.W, SL.H, UI.groups[UI.page])
    for p in PAGES
        UI.nav[p[1]].Value := "HBITMAP:" RenderNav(p[2], p[3], p[1] = UI.page)
}

ShowMoreMenu(btn, *) {
    static m := 0
    if !m {
        m := Menu()
        m.Add("Open settings folder", (*) => OpenSettingsFolder())
        m.Add("Report a bug", (*) => Run(APP.repo LINKS[1][2]))
        m.Add("Project page on GitHub", (*) => Run(APP.repo))
        m.Add()
        m.Add("Restart app", (*) => RestartApp())
        m.Add("Exit app", (*) => ExitApp())
    }
    old := PMv2()
    WinGetPos(&x, &y, &w, &h, btn.Hwnd)
    CoordMode("Menu", "Screen")
    m.Show(x, y + h)
    PMv2(old)
}

ShowInfoTip(hwnd) {
    if !UI.infoTips.Has(hwnd)
        return
    UI.tipFor := hwnd
    old := PMv2()
    WinGetPos(&x, &y, &w, &h, hwnd)
    CoordMode("ToolTip", "Screen")
    ToolTip(UI.infoTips[hwnd], x + w + Px(4), y + h + Px(4))
    PMv2(old)
    SetTimer(CheckInfoTip, 250)
}

CheckInfoTip() {
    MouseGetPos(, , , &over, 2)
    if (over = UI.tipFor)
        return
    ToolTip()
    UI.tipFor := 0
    SetTimer(CheckInfoTip, 0)
}

OnSettingsMouseMove(wParam, lParam, msg, hwnd) {
    if (UI.gui && UI.infoTips.Has(hwnd) && UI.tipFor != hwnd)
        ShowInfoTip(hwnd)
}

; Moved to a monitor with another scale: lay everything out again
OnSettingsDpiChanged(wParam, lParam, msg, hwnd) {
    if (!UI.gui || hwnd != UI.gui.Hwnd)
        return
    if ((wParam & 0xFFFF) = UI.dpi)         ; e.g. first shown on this monitor: already laid out for it
        return 0
    UI.dpi := wParam & 0xFFFF, UI.k := UI.dpi / 96
    ApplyLayout()
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", NumGet(lParam, 0, "int"), "int", NumGet(lParam, 4, "int")
          , "int", NumGet(lParam, 8, "int") - NumGet(lParam, 0, "int"), "int", NumGet(lParam, 12, "int") - NumGet(lParam, 4, "int")
          , "uint", 0x14)                                   ; SWP_NOZORDER | SWP_NOACTIVATE
    return 0
}

ApplyLayout() {
    old := PMv2()
    for item in UI.items {
        if (item.ctl.Type != "Pic")             ; pictures have no font
            ItemFont(item.ctl, item)
        if (item.h = "")
            item.ctl.Move(Px(item.x), Px(item.y), Px(item.w))
        else
            item.ctl.Move(Px(item.x), Px(item.y), Px(item.w), Px(item.h))
    }
    for icon in UI.icons
        icon.ctl.Value := IconSpec(icon.size)
    RenderChrome()
    RefreshSettings()
    DllCall("InvalidateRect", "ptr", UI.gui.Hwnd, "ptr", 0, "int", 1)
    PMv2(old)
}

; ---- State -> window -----------------------------------------------------------

FlipSwitch(name) {
    if (!UI.gui || !UI.tg[name].Enabled)
        return
    switch name {
        case "remapping":
            SetPaused(!PAUSED, false)
        case "autostart":
            SetAutostart(!FileExist(APP.lnk))
            UpdateTray()
            RefreshSettings()
        case "distinguish":
            DRAFT.launchAnySide := !DRAFT.launchAnySide
            CommitDraft()
        default:
            DRAFT.%name% := !DRAFT.%name%
            if (name = "launchEnabled" && !DRAFT.launchEnabled && CAP.active && CAP.target = "launch")
                CaptureCancel()
            CommitDraft()
    }
}

; Applies and saves the draft if it's complete; otherwise the row that needs
; something says so and the active settings stay as they were
CommitDraft() {
    global CFG
    UI.problem := ValidateSettings(DRAFT, &where), UI.problemWhere := where
    if (UI.problem != "") {
        RefreshSettings()
        return false
    }
    themeChanged := UI.gui && ThemeName(DRAFT.theme) != UI.themeName
    hidingIcon := CFG.trayIcon && !DRAFT.trayIcon
    CFG := CloneSettings(DRAFT)
    try WriteSettings(SETTINGS_PATH, CFG)
    catch as e
        GlassToast("Couldn't save the settings", e.Message, "warn")
    ApplySettings()
    ApplyAppTheme(CFG.theme)
    ScheduleUpdateCheck()
    if hidingIcon
        GlassToast("The tray icon is hidden", "To see the settings again, open the app again", "info", 7000)
    if themeChanged
        SetTimer(RebuildSettings, -1)       ; not from inside the control's own event
    else
        RefreshSettings()
    return true
}

RefreshSettings() {
    if !UI.gui
        return
    old := PMv2()
    d := DRAFT, th := UI.th
    listening := CAP.active ? CAP.target : ""
    isKey := d.mode = "Key", on := d.launchEnabled ? 1 : 0

    UI.status.Value := PAUSED ? "Paused" : "Active"
    UI.status.SetFont("c" Hex6(PAUSED ? th.warn : th.ok))

    ; General
    SetSwitch("remapping", !PAUSED)
    SetSwitch("autostart", FileExist(APP.lnk) != "")
    SetSwitch("trayIcon", d.trayIcon)
    UI.theme.Value := ChoiceIndex(THEME_PREFS, d.theme)

    ; Keys
    SetKeyView("source", UI.srcKeys, [], d.sourceVK, d.sourceSC, false, listening = "source")
    UI.srcBtn.Text := listening = "source" ? "Cancel" : "Change…"
    UI.mode.Value := ChoiceIndex(MODES, d.mode)
    UI.actionInfo.Value := isKey ? "Presses the key or shortcut chosen below instead." : ACTION_INFO[d.mode]
    SetKeyView("target", UI.targetKeys, d.targetMods, d.targetVK, d.targetSC, false, listening = "target", !isKey)
    UI.targetKeys.Enabled := isKey, UI.targetBtn.Enabled := isKey
    UI.targetBtn.Text := listening = "target" ? "Cancel" : "Change…"
    UI.targetTitle.SetFont("c" Hex6(isKey ? th.text : th.dim))
    RowNote(UI.srcDesc, "source", KeyCode(d.sourceVK, d.sourceSC))
    RowNote(UI.targetDesc, "target", isKey ? KeyCode(d.targetVK, d.targetSC) : "Not used by this action", !isKey)

    SetSwitch("launchEnabled", on)
    SetKeyView("launch", UI.launchKeys, d.launchMods, d.launchVK, d.launchSC, d.launchAnySide, listening = "launch", !on)
    UI.launchKeys.Enabled := on
    UI.launchBtn.Text := listening = "launch" ? "Cancel" : "Change…"
    SetSwitch("distinguish", !d.launchAnySide, !on)
    for ctl in [UI.launchBtn, UI.auto, UI.browse]
        ctl.Enabled := on
    for ctl in [UI.launchTitle, UI.sidesTitle, UI.appTitle]
        ctl.SetFont("c" Hex6(on ? th.text : th.dim))
    RowNote(UI.launchDesc, "launch", KeyCode(d.launchVK, d.launchSC), !on)
    UpdateApp()

    ; Notifications
    UI.toastWhen.Value := ChoiceIndex(TOAST_WHENS, d.toastWhen)
    UI.toastPos.Value := ChoiceIndex(TOAST_POSITIONS, d.toastPosition)
    UI.toastAnim.Value := ChoiceIndex(TOAST_ANIMS, d.toastAnim)

    ; Updates
    SetSwitch("checkUpdates", d.checkUpdates)
    UpdateUpdatesRow()

    ; Advanced
    SetSwitch("matchSC", d.matchSC)
    UI.settingsPath.Value := SETTINGS_PATH
    PMv2(old)
}

; A row's description, or what's missing (in red) if the problem is there
RowNote(ctl, where, normal, dim := false) {
    th := UI.th
    if (UI.problemWhere = where) {
        ctl.Value := where = "target" ? "Click Change… to choose it." : "Add a modifier, e.g. Right Ctrl."
        ctl.SetFont("c" Hex6(th.warn))
    } else {
        ctl.Value := normal
        ctl.SetFont("c" Hex6(dim ? th.dim : th.sub))
    }
}

KeyCode(vk, sc) => vk ? Format("Code: VK {:X} · SC {:X}", vk, sc) : "Not set yet"

SetKeyView(name, pic, mods, vk, sc, anySide, listen, dim := false) {
    parts := vk ? ComboParts(mods, vk, sc, anySide) : []
    UI.keyText[name] := listen ? "listening" : vk ? ComboLabel(mods, vk, sc, anySide) : "Not set"
    pic.Value := "HBITMAP:" RenderKeys(parts, "", listen, dim)
}

SetSwitch(name, on, dim := false) {
    UI.tgState[name] := on ? 1 : 0
    UI.tg[name].Enabled := !dim
    UI.tg[name].Value := "HBITMAP:" RenderSwitch(on, dim)
}

ChoiceIndex(list, value) {
    for i, item in list
        if (item = value)
            return i
    return 1
}

UpdateApp() {
    if !UI.gui
        return
    p := DRAFT.launchPath, th := UI.th, color := th.sub
    if (p = "auto") {
        name := NS.label != "" ? NS.label : "NitroSense"
        if !NS.checked
            status := "Looking for it…"
        else if (NS.target != "") {
            SplitPath(NS.target, &file)
            status := SubStr(NS.target, 1, 6) = "shell:" ? "found automatically" : "found automatically (" file ")"
            color := th.ok
        } else
            status := "not found: click Browse…", color := th.warn
        status := name ", " status
    } else if (SubStr(p, 1, 6) = "shell:") {
        status := "An app from the Apps folder (chosen by you)"
    } else {
        SplitPath(p, &file)
        if FileExist(p)
            status := file " (chosen by you)"
        else
            status := file ": file not found, click Browse…", color := th.warn
    }
    UI.appStatus.Value := status
    UI.appStatus.SetFont("c" Hex6(DRAFT.launchEnabled ? color : th.dim))
}

UpdateUpdatesRow() {
    if !UI.gui
        return
    th := UI.th, color := th.sub
    switch UPD.state {
        case "checking":
            btn := "Checking…", text := "Looking for a new version…"
        case "available":
            btn := (A_IsCompiled ? "Install " : "Download ") UPD.latest
            text := "A new version is available", color := th.ok
        case "latest":
            btn := "Check now", text := "You're up to date"
        case "error":
            btn := "Check now", text := "Couldn't check. Try again later.", color := th.warn
        default:
            btn := "Check now", text := "Not checked yet"
    }
    UI.updBtn.Text := btn
    UI.updBtn.Enabled := UPD.state != "checking"
    UI.updText.Value := text
    UI.updText.SetFont("c" Hex6(color))
}

DetectForApp() {
    DetectNitroSense()
    UpdateApp()
}

; ---- Window -> settings ----------------------------------------------------------

OnModeChange(ctl, *) {
    DRAFT.mode := MODES[ctl.Value]
    if (CAP.active && CAP.target = "target" && DRAFT.mode != "Key")
        CaptureCancel()
    CommitDraft()
}

OnThemeChange(ctl, *) {
    DRAFT.theme := THEME_PREFS[ctl.Value]
    CommitDraft()
}

AutoApp(*) {
    DRAFT.launchPath := "auto"
    if !NS.checked
        SetTimer(DetectForApp, -1)
    CommitDraft()
}

BrowseApp(*) {
    UI.gui.Opt("+OwnDialogs")
    file := FileSelect(35, , "Choose the app to open", "Programs (*.exe; *.lnk)")   ; 1+2+32: must exist, keep .lnk
    if (file != "") {
        DRAFT.launchPath := file
        CommitDraft()
    }
}

ResetSettings(*) {
    global DRAFT
    UI.gui.Opt("+OwnDialogs")
    if (MsgBox("Put every option back to its default value?", APP.short, "YesNo Icon?") != "Yes")
        return
    CaptureCancel()
    DRAFT := DefaultSettings()
    CommitDraft()
}

; Shows a notification with the position and animation chosen in the window
PreviewToast(*) {
    saved := [GTCFG.position, GTCFG.animation]
    GTCFG.position := DRAFT.toastPosition, GTCFG.animation := DRAFT.toastAnim
    try GlassToast("This is how notifications look"
                 , TOAST_POSITION_LABELS[ChoiceIndex(TOAST_POSITIONS, DRAFT.toastPosition)] " · "
                 . TOAST_ANIM_LABELS[ChoiceIndex(TOAST_ANIMS, DRAFT.toastAnim)], "ok", 3000)
    GTCFG.position := saved[1], GTCFG.animation := saved[2]
}

; Blocking problems only; where = the row that must show it
ValidateSettings(d, &where := "") {
    where := ""
    if (d.mode != "None" && !d.sourceVK)
        return (where := "source", "Choose the key to remap first: click Change… next to Key.")
    if (d.mode = "Key" && !d.targetVK)
        return (where := "target", "Choose the key or shortcut to send: click Change… next to Sends.")
    if d.launchEnabled {
        if !d.launchVK
            return (where := "launch", "Choose the shortcut that opens NitroSense, or turn it off.")
        if (!d.launchMods.Length && d.mode != "None" && SameKey(d.launchVK, d.launchSC, d.sourceVK, d.sourceSC))
            return (where := "launch", "The shortcut to open NitroSense is the key you are remapping, so the remap would never run. Add a modifier, for example Right Ctrl.")
    }
    return ""
}

SameKey(vk1, sc1, vk2, sc2) => vk1 = vk2 && (!sc1 || !sc2 || sc1 = sc2)

CloseSettings(*) {
    CaptureCancel()
    DestroySettings()
}

DestroySettings() {
    if !UI.gui
        return
    ToolTip()
    SetTimer(CheckInfoTip, 0)
    g := UI.gui
    UI.gui := 0
    g.Destroy()
    for handle in [UI.brushWin, UI.brushCard, UI.bgBmp]
        if handle
            DllCall("DeleteObject", "ptr", handle)
    UI.bgBmp := 0
    if UI.tok
        DllCall("gdiplus\GdiplusShutdown", "ptr", UI.tok), UI.tok := 0
}

; Rebuilds the window (theme change) at the same place and section
RebuildSettings() {
    if !UI.gui
        return
    old := PMv2()
    WinGetPos(&wx, &wy, , , UI.gui.Hwnd)
    PMv2(old)
    page := UI.page
    CaptureCancel()
    DestroySettings()
    BuildSettings(page, wx, wy)
}

; ---- Theme -----------------------------------------------------------------

; "light" or "dark": the user's choice, or Windows' app mode for "System"
ThemeName(pref) {
    if (pref = "Light" || pref = "Dark")
        return StrLower(pref)
    try return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme") ? "light" : "dark"
    return "light"
}

; Dark or light context menus (tray menu) for this process. Undocumented
; uxtheme exports, available since Windows 10 1809; silently skipped before.
ApplyAppTheme(pref) {
    try {
        DllCall(UxOrdinal(135), "int", pref = "Dark" ? 2 : pref = "Light" ? 3 : 1)   ; SetPreferredAppMode
        DllCall(UxOrdinal(136))                                                        ; FlushMenuThemes
    }
}

UxOrdinal(n) {
    static ux := DllCall("LoadLibrary", "str", "uxtheme", "ptr")
    return DllCall("GetProcAddress", "ptr", ux, "ptr", n, "ptr")
}

ThemeCtl(ctl, kind := "button") {
    dark := UI.th.dark
    try DllCall(UxOrdinal(133), "ptr", ctl.Hwnd, "int", dark)                      ; AllowDarkModeForWindow
    DllCall("uxtheme\SetWindowTheme", "ptr", ctl.Hwnd
          , "str", dark ? (kind = "combo" ? "DarkMode_CFD" : "DarkMode_Explorer") : "Explorer", "ptr", 0)
}

ThemeTitleBar(hwnd) {
    static dwm := DllCall("LoadLibrary", "str", "dwmapi", "ptr")
    v := Buffer(4)
    NumPut("int", UI.th.dark ? 1 : 0, v)
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 20, "ptr", v, "uint", 4)   ; dark title bar
    NumPut("uint", Bgr(UI.th.win), v)
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 35, "ptr", v, "uint", 4)   ; caption color (Windows 11)
}

; Windows switched between light and dark
OnSettingChange(wParam, lParam, msg, hwnd) {
    if (hwnd != A_ScriptHwnd || !lParam)
        return
    try {
        if (StrGet(lParam) != "ImmersiveColorSet")
            return
    } catch
        return
    ApplyAppTheme(CFG.theme)
    if (UI.gui && ThemeName(DRAFT.theme) != UI.themeName)
        SetTimer(RebuildSettings, -300)
}

OnSettingsErase(wParam, lParam, msg, hwnd) {
    if (!UI.gui || hwnd != UI.gui.Hwnd || !UI.bgBmp)
        return
    hdc := DllCall("CreateCompatibleDC", "ptr", wParam, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", UI.bgBmp, "ptr")
    DllCall("BitBlt", "ptr", wParam, "int", 0, "int", 0, "int", UI.bgW, "int", UI.bgH
          , "ptr", hdc, "int", 0, "int", 0, "uint", 0x00CC0020)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("DeleteDC", "ptr", hdc)
    return 1
}

OnSettingsCtlColorBtn(wParam, lParam, msg, hwnd) {
    if (UI.gui && hwnd = UI.gui.Hwnd)
        return UI.cardBtns.Has(lParam) ? UI.brushCard : UI.brushWin
}

OnSettingsCtlColorStatic(wParam, lParam, msg, hwnd) {
    if (UI.gui && hwnd = UI.gui.Hwnd && UI.cardStatics.Has(lParam))
        return UI.brushCard
}

OnSettingsCtlColorList(wParam, lParam, msg, hwnd) {
    if (!UI.gui || hwnd != UI.gui.Hwnd || !UI.th.dark)
        return
    DllCall("SetTextColor", "ptr", wParam, "uint", Bgr(UI.th.text))
    DllCall("SetBkColor", "ptr", wParam, "uint", Bgr(UI.th.card))
    return UI.brushCard
}

; ---- Drawing (GDI+, reusing the toast library's helpers) --------------------

Argb(rgb, alpha := 0xFF) => (alpha << 24) | rgb
Bgr(rgb) => ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
Hex6(rgb) => Format("{:06X}", rgb)

GdipStart() {
    DllCall("LoadLibrary", "str", "gdiplus", "ptr")
    si := Buffer(24, 0), tok := 0
    NumPut("uint", 1, si)
    DllCall("gdiplus\GdiplusStartup", "ptr*", &tok, "ptr", si, "ptr", 0)
    return tok
}

Canvas(wL, hL, bg) {
    w := Round(wL * UI.k), h := Round(hL * UI.k), g := 0
    bmp := GT_Bitmap(w, h)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &g)
    GT_Quality(g)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", g, "int", 5)     ; ClearType: the background is opaque
    DllCall("gdiplus\GdipGraphicsClear", "ptr", g, "uint", Argb(bg))
    return {bmp: bmp, g: g, w: w, h: h}
}

; Turns the canvas into an HBITMAP; dim fades it towards the background
CanvasDone(cv, bg, dim := false) {
    if dim {
        brush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", Argb(bg, 0xA8), "ptr*", &brush)
        DllCall("gdiplus\GdipFillRectangle", "ptr", cv.g, "ptr", brush, "float", 0, "float", 0, "float", cv.w, "float", cv.h)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
    }
    hbm := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", cv.bmp, "ptr*", &hbm, "uint", Argb(bg))
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", cv.g)
    DllCall("gdiplus\GdipDisposeImage", "ptr", cv.bmp)
    return hbm
}

NewFormat(align) {                      ; 0 left, 1 center, 2 right; vertically centered, no wrap
    fmt := 0
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0x1000, "int", 0, "ptr*", &fmt)
    DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmt, "int", align)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", fmt, "int", 1)
    return fmt
}

FillPathFree(g, p, argb) {
    GT_FillPath(g, p, argb)
    DllCall("gdiplus\GdipDeletePath", "ptr", p)
}

StrokePathFree(g, p, argb, width) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", argb, "float", width, "int", 2, "ptr*", &pen)
    DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", pen, "ptr", p)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    DllCall("gdiplus\GdipDeletePath", "ptr", p)
}

FillCircle(g, x, y, d, argb) {
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &brush)
    DllCall("gdiplus\GdipFillEllipse", "ptr", g, "ptr", brush, "float", x, "float", y, "float", d, "float", d)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
}

; Window background: the rounded card groups (with row dividers) on the window color
RenderBackground(wL, hL, groups) {
    th := UI.th, k := UI.k
    cv := Canvas(wL, hL, th.win)
    for c in groups {
        x := Round(c.x * k), y := Round(c.y * k), cw := Round(c.w * k), ch := Round(c.h * k)
        FillPathFree(cv.g, GT_RoundPath(x, y, cw, ch, 8 * k), Argb(th.card))
        StrokePathFree(cv.g, GT_RoundPath(x + 0.5, y + 0.5, cw - 1, ch - 1, 8 * k), Argb(th.border), 1)
        for dy in c.dividers {
            pen := 0, ly := y + Round(dy * k) + 0.5
            DllCall("gdiplus\GdipCreatePen1", "uint", Argb(th.border), "float", 1, "int", 2, "ptr*", &pen)
            DllCall("gdiplus\GdipDrawLine", "ptr", cv.g, "ptr", pen, "float", x + 1, "float", ly, "float", x + cw - 1, "float", ly)
            DllCall("gdiplus\GdipDeletePen", "ptr", pen)
        }
    }
    return CanvasDone(cv, th.win)
}

; A sidebar entry: icon glyph and label; the selected one gets a pill and an accent bar
RenderNav(label, glyph, selected) {
    th := UI.th, k := UI.k
    cv := Canvas(SL.side - 16, 36, th.win), g := cv.g
    if selected {
        FillPathFree(g, GT_RoundPath(0, 0, cv.w, cv.h, 5 * k), Argb(th.navSel))
        FillPathFree(g, GT_RoundPath(0, (cv.h - 16 * k) / 2, 3 * k, 16 * k, 1.5 * k), Argb(th.accent))
    }
    famI := GT_Family("Segoe Fluent Icons")
    if !famI
        famI := GT_Family("Segoe MDL2 Assets")
    famT := GT_Family("Segoe UI")
    fmt := NewFormat(0)
    if famI {
        fi := GT_Font(famI, 15 * k, 0)
        GT_Text(g, Chr(glyph), fi, Argb(th.text), 14 * k, 0, 24 * k, cv.h, fmt)
        DllCall("gdiplus\GdipDeleteFont", "ptr", fi)
        DllCall("gdiplus\GdipDeleteFontFamily", "ptr", famI)
    }
    ft := GT_Font(famT, 13.5 * k, selected ? 1 : 0)
    GT_Text(g, label, ft, Argb(th.text), 46 * k, 0, cv.w - 50 * k, cv.h, fmt)
    DllCall("gdiplus\GdipDeleteFont", "ptr", ft)
    DllCall("gdiplus\GdipDeleteFontFamily", "ptr", famT)
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
    return CanvasDone(cv, th.win)
}

; A key or shortcut as keycaps, with its codes on the right
RenderKeys(parts, code, listen, dim) {
    th := UI.th, k := UI.k
    cv := Canvas(UI.kvW, 34, th.card), g := cv.g
    famR := GT_Family("Segoe UI"), famSB := GT_Family("Segoe UI Semibold")
    fam := famSB ? famSB : famR
    fmtL := NewFormat(0), fmtC := NewFormat(1), fmtR := NewFormat(2)
    fSmall := GT_Font(famR, 11 * k, 0), font := 0
    avail := cv.w
    if (code != "") {
        GT_Text(g, code, fSmall, Argb(th.sub), 0, 0, cv.w, cv.h, fmtR)
        avail -= GT_MeasureW(g, code, fSmall, fmtL) + 14 * k
    }
    capH := Round(26 * k), y0 := Round((cv.h - capH) / 2 - k), rad := 6 * k
    if listen {
        font := GT_Font(fam, 12.5 * k, 0), text := "Press a key or shortcut…"
        cw := Min(avail - 2 * k, GT_MeasureW(g, text, font, fmtL) + 26 * k)
        FillPathFree(g, GT_RoundPath(k, y0, cw, capH + 2 * k, rad), Argb(th.accent, 0x24))
        StrokePathFree(g, GT_RoundPath(k, y0, cw, capH + 2 * k, rad), Argb(th.accent), 1.5 * k)
        GT_Text(g, text, font, Argb(th.accent), k, y0, cw, capH + 2 * k, fmtC)
    } else if !parts.Length {
        font := GT_Font(famR, 13 * k, 0)
        GT_Text(g, "Not set: click Change…", font, Argb(th.sub), 0, 0, avail, cv.h, fmtL)
    } else {
        size := 13
        loop {                              ; shrink the text if the shortcut is long
            font := GT_Font(fam, size * k, 0)
            plusW := GT_MeasureW(g, "+", font, fmtL) + 12 * k, total := 0
            for i, part in parts
                total += GT_MeasureW(g, part, font, fmtL) + 20 * k + (i > 1 ? plusW : 0)
            if (total <= avail || size <= 10)
                break
            DllCall("gdiplus\GdipDeleteFont", "ptr", font)
            size -= 1
        }
        x := k
        for i, part in parts {
            if (i > 1) {
                GT_Text(g, "+", font, Argb(th.sub), x, 0, plusW, cv.h, fmtC)
                x += plusW
            }
            capW := GT_MeasureW(g, part, font, fmtL) + 20 * k
            FillPathFree(g, GT_RoundPath(x, y0 + 2 * k, capW, capH, rad), Argb(th.keyShade))
            FillPathFree(g, GT_RoundPath(x, y0, capW, capH, rad), Argb(th.keyFace))
            StrokePathFree(g, GT_RoundPath(x + 0.5, y0 + 0.5, capW - 1, capH - 1, rad), Argb(th.keyEdge), 1)
            GT_Text(g, part, font, Argb(th.keyText), x, y0, capW, capH, fmtC)
            x += capW
        }
    }
    for f in [font, fSmall]
        if f
            DllCall("gdiplus\GdipDeleteFont", "ptr", f)
    for fm in [famR, famSB]
        if fm
            DllCall("gdiplus\GdipDeleteFontFamily", "ptr", fm)
    for fmt in [fmtL, fmtC, fmtR]
        DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
    return CanvasDone(cv, th.card, dim)
}

; Windows 11 style on/off switch
RenderSwitch(on, dim) {
    th := UI.th, k := UI.k
    cv := Canvas(40, 20, th.card), g := cv.g
    inset := k, ht := cv.h - 2 * inset
    if on {
        FillPathFree(g, GT_RoundPath(inset, inset, cv.w - 2 * inset, ht, ht / 2), Argb(th.on))
        d := 12 * k
        FillCircle(g, cv.w - inset - 4 * k - d, (cv.h - d) / 2, d, Argb(th.knobOn))
    } else {
        StrokePathFree(g, GT_RoundPath(inset, inset, cv.w - 2 * inset, ht, ht / 2), Argb(th.off), 1.2 * k)
        d := 10 * k
        FillCircle(g, inset + 4 * k, (cv.h - d) / 2, d, Argb(th.knobOff))
    }
    return CanvasDone(cv, th.card, dim)
}
