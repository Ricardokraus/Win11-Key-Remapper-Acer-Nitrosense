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

; Settings window colors (RGB). "dim" is used for disabled rows.
THEMES := Map("light", {dark: false, win: 0xF3F3F3, card: 0xFFFFFF, border: 0xE3E3E3
                      , text: 0x1A1A1A, sub: 0x616161, dim: 0xA8A8A8
                      , on: 0x1E9E48, knobOn: 0xFFFFFF, off: 0x8A8A8A, knobOff: 0x616161
                      , keyFace: 0xFAFAFA, keyEdge: 0xCFCFCF, keyShade: 0xC9C9C9, keyText: 0x1A1A1A
                      , accent: 0x1E9E48, ok: 0x13803A, warn: 0xC42B1C}
            , "dark", {dark: true, win: 0x202020, card: 0x2B2B2B, border: 0x3A3A3A
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
        ShowSettings(true)
        SetTimer(() => GlassToast("Welcome to " APP.short, "Choose what the key should do and click Save"), -700)
    } else if args.updated
        SetTimer(() => GlassToast("Updated to version " APP.version, "See what's new on the GitHub release page"), -2000)
    else if CFG.showToast
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
          , showToast: true, toastPosition: "TopCenter", toastAnim: "Slide"
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
          , showToast: IniBool(path, "General", "ShowToast", d.showToast)
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
    IniWrite(c.showToast ? 1 : 0, path, "General", "ShowToast")
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
    RefreshSettings()
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
        if CFG.showToast
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
        if CFG.showToast
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
    UpdateTray()
}

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

TogglePause() {
    global PAUSED
    ReleasePresses()
    PAUSED := !PAUSED
    UpdateTray()
    RefreshSettings()                       ; status line, if the window is open
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
    if UI.gui {
        UI.autostartOn := on ? 1 : 0
        RefreshSettings()
    }
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
        if (manual || (CFG.showToast && UPD.notified != UPD.latest))
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
; Standard Win32 controls can't draw rounded cards, keycaps or switches, so
; those are drawn with GDI+ into bitmaps: the cards are painted on
; WM_ERASEBKGND, the keys and switches are Picture controls redrawn by
; RefreshSettings. Colors follow Windows' light/dark mode unless the Theme
; setting picks one; buttons and drop-down lists use the system dark themes.

ShowSettings(firstRun := false) {
    global DRAFT
    if UI.gui {
        UI.gui.Show()
        return
    }
    DRAFT := CloneSettings(CFG)
    BuildSettings(firstRun || FileExist(APP.lnk) != "")
    if !NS.checked
        SetTimer(DetectForApp, -150)        ; after the window is on screen
}

BuildSettings(autostartOn, posX := "", posY := "") {
    static hooked := false
    if !hooked {
        OnMessage(0x14, OnSettingsErase)            ; WM_ERASEBKGND: paint the cards
        OnMessage(0x135, OnSettingsCtlColorBtn)     ; WM_CTLCOLORBTN: button corners
        OnMessage(0x134, OnSettingsCtlColorList)    ; WM_CTLCOLORLISTBOX: dark drop-down lists
        hooked := true
    }
    UI.themeName := ThemeName(DRAFT.theme)
    th := UI.th := THEMES[UI.themeName]
    UI.k := A_ScreenDPI / 96
    UI.tok := GdipStart()
    UI.autostartOn := autostartOn ? 1 : 0
    UI.keyText := Map(), UI.tg := Map(), UI.tgState := Map(), UI.cardBtns := Map()
    UI.brushWin := DllCall("CreateSolidBrush", "uint", Bgr(th.win), "ptr")
    UI.brushCard := DllCall("CreateSolidBrush", "uint", Bgr(th.card), "ptr")

    ; Layout in logical pixels (Windows scales the window and controls by
    ; DPI). Left column: the remap and the NitroSense shortcut. Right column:
    ; notifications and general options.
    M := 20, gap := 12, pad := 16, leftW := 500, rightW := 400
    CW := M + leftW + gap + rightW + M
    xL := M + pad                               ; left column: row labels
    xK := xL + 70                               ;   keys and values
    xB := M + leftW - pad - 96                  ;   "Change…" buttons
    xR := M + leftW - pad                       ;   right edge inside the cards
    UI.kvW := xB - 10 - xK
    rx := M + leftW + gap                       ; right column
    rL := rx + pad, rK := rL + 90, rR := rx + rightW - pad
    c3 := {x: rx, y: 70, w: rightW, h: 184}
    c4 := {x: rx, y: c3.y + c3.h + 10, w: rightW, h: 208}
    c1 := {x: M, y: 70, w: leftW, h: 210}
    c2 := {x: M, y: c1.y + c1.h + 10, w: leftW, h: c4.y + c4.h - (c1.y + c1.h + 10)}
    footY := c2.y + c2.h + 14, CH := footY + 30 + 18
    UI.bgW := Round(CW * UI.k), UI.bgH := Round(CH * UI.k)
    UI.bgBmp := RenderBackground(CW, CH, [c1, c2, c3, c4])

    g := Gui("-MinimizeBox -MaximizeBox", APP.name)
    UI.gui := g
    g.BackColor := Hex6(th.win)
    g.MarginX := 0, g.MarginY := 0
    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    ; Header: icon, name and what the app is doing right now
    try g.AddPicture("x" M " y16 w32 h32" (A_IsCompiled ? " Icon1" : ""), A_IsCompiled ? A_ScriptFullPath : IconPath())
    NewLabel(g, "x64 y11 w600 h26", APP.short, th.win, th.text, "s14 w600")
    UI.status := NewLabel(g, "x64 y38 w" (CW - 84) " h18 0x4080", "", th.win, th.sub, "s9")

    ; Card 1: the key and what it does
    NewLabel(g, "x" xL " y" (c1.y + 12) " w300 h22", "Remap a key", th.card, th.text, "s11 w600")
    y := c1.y + 44
    NewLabel(g, "x" xL " y" (y + 7) " w66 h20", "Key", th.card, th.sub)
    UI.srcKeys := NewKeyView(g, "source", xK, y)
    UI.srcBtn := NewButton(g, "x" xB " y" (y + 2) " w96 h30", "Change…", true)
    y := c1.y + 86
    NewSwitch(g, "matchSC", xR - 40, y
            , NewLabel(g, "x" xL " y" y " w" (xR - 50 - xL) " h20", "Exact key match (recommended for vendor keys like NitroSense)", th.card, th.sub, "s9"))
    y := c1.y + 118
    NewLabel(g, "x" xL " y" (y + 5) " w66 h20", "Action", th.card, th.sub)
    g.SetFont("s10 w400 c" Hex6(th.text), "Segoe UI")
    UI.mode := g.AddDropDownList("x" xK " y" y " w" (xR - xK) " AltSubmit", MODE_LABELS)
    ThemeCtl(UI.mode, "combo")
    y := c1.y + 158
    UI.actionInfo := NewLabel(g, "x" xK " y" (y + 2) " w" (xR - xK) " h34", "", th.card, th.sub, "s9")
    UI.targetLbl := NewLabel(g, "x" xL " y" (y + 7) " w66 h20", "Sends", th.card, th.sub)
    UI.targetKeys := NewKeyView(g, "target", xK, y)
    UI.targetBtn := NewButton(g, "x" xB " y" (y + 2) " w96 h30", "Change…", true)

    ; Card 2: shortcut that opens NitroSense
    UI.launchTitle := NewLabel(g, "x" xL " y" (c2.y + 12) " w380 h22", "Open NitroSense with a shortcut", th.card, th.text, "s11 w600")
    NewSwitch(g, "launchEnabled", xR - 40, c2.y + 13, UI.launchTitle)
    y := c2.y + 46
    UI.launchLbl := NewLabel(g, "x" xL " y" (y + 7) " w66 h20", "Shortcut", th.card, th.sub)
    UI.launchKeys := NewKeyView(g, "launch", xK, y)
    UI.launchBtn := NewButton(g, "x" xB " y" (y + 2) " w96 h30", "Change…", true)
    y := c2.y + 92
    UI.anyLbl := NewLabel(g, "x" xL " y" y " w" (xR - 50 - xL) " h20", "Left and right Ctrl, Alt, Shift and Win both work", th.card, th.text)
    NewSwitch(g, "launchAnySide", xR - 40, y, UI.anyLbl)
    y := c2.y + 126
    UI.appLbl := NewLabel(g, "x" xL " y" (y + 7) " w66 h20", "App", th.card, th.sub)
    UI.appName := NewLabel(g, "x" xK " y" (y - 1) " w" (xB - 82 - xK) " h20 0x4080", "", th.card, th.text)
    UI.appStatus := NewLabel(g, "x" xK " y" (y + 18) " w" (xB - 82 - xK) " h18 0x4080", "", th.card, th.sub, "s9")
    UI.auto := NewButton(g, "x" (xB - 72) " y" (y + 2) " w64 h30", "Auto", true)
    UI.browse := NewButton(g, "x" xB " y" (y + 2) " w96 h30", "Browse…", true)

    ; Card 3: notifications
    NewLabel(g, "x" rL " y" (c3.y + 12) " w300 h22", "Notifications", th.card, th.text, "s11 w600")
    y := c3.y + 44
    NewSwitch(g, "showToast", rR - 40, y
            , NewLabel(g, "x" rL " y" y " w" (rR - 50 - rL) " h20", "Show when Windows starts or unlocks", th.card, th.text))
    y := c3.y + 76
    NewLabel(g, "x" rL " y" (y + 5) " w86 h20", "Position", th.card, th.sub)
    g.SetFont("s10 w400 c" Hex6(th.text), "Segoe UI")
    UI.toastPos := g.AddDropDownList("x" rK " y" y " w" (rR - rK) " AltSubmit", TOAST_POSITION_LABELS)
    ThemeCtl(UI.toastPos, "combo")
    y := c3.y + 110
    NewLabel(g, "x" rL " y" (y + 5) " w86 h20", "Animation", th.card, th.sub)
    g.SetFont("s10 w400 c" Hex6(th.text), "Segoe UI")
    UI.toastAnim := g.AddDropDownList("x" rK " y" y " w" (rR - rK) " AltSubmit", TOAST_ANIM_LABELS)
    ThemeCtl(UI.toastAnim, "combo")
    y := c3.y + 142
    UI.preview := NewButton(g, "x" rK " y" y " w200 h30", "Show a test notification", true)

    ; Card 4: general options
    NewLabel(g, "x" rL " y" (c4.y + 12) " w300 h22", "General", th.card, th.text, "s11 w600")
    rows := [["autostart", "Start with Windows"], ["trayIcon", "Show the icon in the tray"]
           , ["checkUpdates", "Check for updates automatically"]]
    for i, row in rows {
        y := c4.y + 44 + (i - 1) * 30
        NewSwitch(g, row[1], rR - 40, y
                , NewLabel(g, "x" rL " y" y " w" (rR - 50 - rL) " h20", row[2], th.card, th.text))
    }
    y := c4.y + 134
    NewLabel(g, "x" rL " y" y " w100 h20", "Theme", th.card, th.text)
    g.SetFont("s10 w400 c" Hex6(th.text), "Segoe UI")
    UI.theme := g.AddDropDownList("x" (rR - 140) " y" (y - 4) " w140 AltSubmit", THEME_PREFS)
    ThemeCtl(UI.theme, "combo")
    y := c4.y + 166
    UI.updBtn := NewButton(g, "x" rL " y" y " w150 h30", "Check now", true)
    UI.updText := NewLabel(g, "x" (rL + 160) " y" (y + 6) " w" (rR - rL - 160) " h20 0x4080", "", th.card, th.sub, "s9")

    ; Footer
    UI.reset := NewButton(g, "x" M " y" footY " w140 h30", "Reset to defaults")
    NewLabel(g, "x" (M + 156) " y" (footY + 7) " w200 h18", "Version " APP.version, th.win, th.sub, "s9")
    UI.cancel := NewButton(g, "x" (CW - M - 200) " y" footY " w96 h30", "Cancel")
    UI.save := NewButton(g, "x" (CW - M - 96) " y" footY " w96 h30 Default", "Save")

    UI.srcBtn.OnEvent("Click", (*) => CaptureToggle("source"))
    UI.targetBtn.OnEvent("Click", (*) => CaptureToggle("target"))
    UI.launchBtn.OnEvent("Click", (*) => CaptureToggle("launch"))
    UI.mode.OnEvent("Change", OnModeChange)
    UI.toastPos.OnEvent("Change", (ctl, *) => DRAFT.toastPosition := TOAST_POSITIONS[ctl.Value])
    UI.toastAnim.OnEvent("Change", (ctl, *) => DRAFT.toastAnim := TOAST_ANIMS[ctl.Value])
    UI.preview.OnEvent("Click", PreviewToast)
    UI.theme.OnEvent("Change", OnThemeChange)
    UI.updBtn.OnEvent("Click", (*) => UpdateAction())
    UI.auto.OnEvent("Click", AutoApp)
    UI.browse.OnEvent("Click", BrowseApp)
    UI.reset.OnEvent("Click", ResetDraft)
    UI.cancel.OnEvent("Click", CloseSettings)
    UI.save.OnEvent("Click", SaveFromGui)

    ThemeTitleBar(g.Hwnd)
    RefreshSettings()
    showOpts := "w" CW " h" CH
    if (posX != "")
        showOpts .= " Hide"
    g.Show(showOpts)
    if (posX != "") {                       ; rebuilt (theme change): keep it where it was
        WinMove(posX, posY, , , g.Hwnd)
        g.Show()
    }
}

NewLabel(g, opts, text, bg, color, font := "s10 w400") {
    g.SetFont(font " c" Hex6(color), "Segoe UI")
    return g.AddText(opts " Background" Hex6(bg), text)
}

NewButton(g, opts, text, onCard := false) {
    g.SetFont("s10 w400 c" Hex6(UI.th.text), "Segoe UI")
    btn := g.AddButton(opts, text)
    ThemeCtl(btn)
    if onCard
        UI.cardBtns[btn.Hwnd] := true
    return btn
}

; The keys of a shortcut drawn as keycaps; click = same as "Change…"
NewKeyView(g, name, x, y) {
    pic := g.AddPicture("x" x " y" y " w" UI.kvW " h34")
    pic.OnEvent("Click", (*) => CaptureToggle(name))
    return pic
}

; On/off switch. Clicking its label flips it too.
NewSwitch(g, name, x, y, label := 0) {
    pic := g.AddPicture("x" x " y" y " w40 h20")
    for ctl in (label ? [pic, label] : [pic]) {
        ctl.OnEvent("Click", (*) => FlipSwitch(name))
        ctl.OnEvent("DoubleClick", (*) => FlipSwitch(name))     ; fast second click
    }
    UI.tg[name] := pic
    return pic
}

FlipSwitch(name) {
    if (!UI.gui || !UI.tg[name].Enabled)
        return
    if (name = "autostart")
        UI.autostartOn := !UI.autostartOn
    else
        DRAFT.%name% := !DRAFT.%name%
    if (name = "launchEnabled" && !DRAFT.launchEnabled && CAP.active && CAP.target = "launch")
        CaptureCancel()
    RefreshSettings()
}

RefreshSettings() {
    if !UI.gui
        return
    d := DRAFT, th := UI.th
    listening := CAP.active ? CAP.target : ""
    isKey := d.mode = "Key", on := d.launchEnabled ? 1 : 0

    UI.status.Value := PAUSED ? "Paused: keys work as usual" : "Active · " Summary(CFG)

    SetKeyView("source", UI.srcKeys, [], d.sourceVK, d.sourceSC, false, listening = "source")
    UI.srcBtn.Text := listening = "source" ? "Cancel" : "Change…"
    SetSwitch("matchSC", d.matchSC)
    UI.mode.Value := ChoiceIndex(MODES, d.mode)
    UI.actionInfo.Value := isKey ? "" : ACTION_INFO[d.mode]
    UI.actionInfo.Visible := !isKey
    for ctl in [UI.targetLbl, UI.targetKeys, UI.targetBtn]
        ctl.Visible := isKey
    if isKey
        SetKeyView("target", UI.targetKeys, d.targetMods, d.targetVK, d.targetSC, false, listening = "target")
    UI.targetBtn.Text := listening = "target" ? "Cancel" : "Change…"

    SetSwitch("launchEnabled", on)
    SetKeyView("launch", UI.launchKeys, d.launchMods, d.launchVK, d.launchSC, d.launchAnySide, listening = "launch", !on)
    UI.launchKeys.Enabled := on
    UI.launchBtn.Text := listening = "launch" ? "Cancel" : "Change…"
    SetSwitch("launchAnySide", d.launchAnySide, !on)
    for ctl in [UI.launchBtn, UI.auto, UI.browse]
        ctl.Enabled := on
    for ctl in [UI.launchLbl, UI.appLbl]
        ctl.SetFont("c" Hex6(on ? th.sub : th.dim))
    for ctl in [UI.anyLbl, UI.appName]
        ctl.SetFont("c" Hex6(on ? th.text : th.dim))
    UpdateApp()

    SetSwitch("showToast", d.showToast)
    UI.toastPos.Value := ChoiceIndex(TOAST_POSITIONS, d.toastPosition)
    UI.toastAnim.Value := ChoiceIndex(TOAST_ANIMS, d.toastAnim)

    SetSwitch("autostart", UI.autostartOn)
    SetSwitch("trayIcon", d.trayIcon)
    SetSwitch("checkUpdates", d.checkUpdates)
    UI.theme.Value := ChoiceIndex(THEME_PREFS, d.theme)
    UpdateUpdatesRow()
}

UpdateUpdatesRow() {
    if !UI.gui
        return
    th := UI.th, color := th.sub
    switch UPD.state {
        case "checking":
            btn := "Checking…", text := ""
        case "available":
            btn := (A_IsCompiled ? "Install " : "Download ") UPD.latest
            text := "A new version is available", color := th.ok
        case "latest":
            btn := "Check now", text := "You're up to date"
        case "error":
            btn := "Check now", text := "Couldn't check. Try again later.", color := th.warn
        default:
            btn := "Check now", text := ""
    }
    UI.updBtn.Text := btn
    UI.updBtn.Enabled := UPD.state != "checking"
    UI.updText.Value := text
    UI.updText.SetFont("c" Hex6(color))
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

SetKeyView(name, pic, mods, vk, sc, anySide, listen, dim := false) {
    parts := vk ? ComboParts(mods, vk, sc, anySide) : []
    code := (vk && !listen) ? Format("VK {:X} · SC {:X}", vk, sc) : ""
    UI.keyText[name] := listen ? "listening" : vk ? ComboLabel(mods, vk, sc, anySide) : "Not set"
    pic.Value := "HBITMAP:" RenderKeys(parts, code, listen, dim)
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
            status := SubStr(NS.target, 1, 6) = "shell:" ? "Found automatically" : "Found automatically (" file ")"
            color := th.ok
        } else
            status := "Not found: click Browse…", color := th.warn
    } else if (SubStr(p, 1, 6) = "shell:") {
        name := "App from the Apps folder", status := "Chosen by you"
    } else {
        SplitPath(p, &file)
        name := file
        if FileExist(p)
            status := "Chosen by you"
        else
            status := "File not found: click Browse…", color := th.warn
    }
    UI.appName.Value := name
    UI.appStatus.Value := status
    UI.appStatus.SetFont("c" Hex6(DRAFT.launchEnabled ? color : th.dim))
}

DetectForApp() {
    DetectNitroSense()
    UpdateApp()
}

OnModeChange(ctl, *) {
    DRAFT.mode := MODES[ctl.Value]
    if (CAP.active && CAP.target = "target" && DRAFT.mode != "Key")
        CaptureCancel()
    RefreshSettings()
}

OnThemeChange(ctl, *) {
    DRAFT.theme := THEME_PREFS[ctl.Value]
    if (ThemeName(DRAFT.theme) != UI.themeName)
        SetTimer(RebuildSettings, -1)       ; not from inside the control's own event
}

AutoApp(*) {
    DRAFT.launchPath := "auto"
    if !NS.checked
        SetTimer(DetectForApp, -1)
    RefreshSettings()
}

BrowseApp(*) {
    UI.gui.Opt("+OwnDialogs")
    file := FileSelect(35, , "Choose the app to open", "Programs (*.exe; *.lnk)")   ; 1+2+32: must exist, keep .lnk
    if (file != "") {
        DRAFT.launchPath := file
        RefreshSettings()
    }
}

ResetDraft(*) {
    global DRAFT
    CaptureCancel()
    DRAFT := DefaultSettings()
    if (ThemeName(DRAFT.theme) != UI.themeName)
        SetTimer(RebuildSettings, -1)
    else
        RefreshSettings()
}

ValidateSettings(d) {
    if (d.mode != "None" && !d.sourceVK)
        return "Choose the key to remap first: click Change… next to Key."
    if (d.mode = "Key" && !d.targetVK)
        return "Choose the key or shortcut to send: click Change… next to Sends. Or pick another action."
    if d.launchEnabled {
        if !d.launchVK
            return "Choose the shortcut that opens NitroSense (Change… next to Shortcut), or turn the shortcut off."
        if (!d.launchMods.Length && d.mode != "None" && SameKey(d.launchVK, d.launchSC, d.sourceVK, d.sourceSC))
            return "The shortcut to open NitroSense is the key you are remapping, so the remap would never run.`n`nAdd a modifier to the shortcut, for example Right Ctrl."
        if (d.launchPath != "auto" && !TargetExists(d.launchPath))
            return "The app to open was not found:`n" d.launchPath
    }
    return ""
}

SameKey(vk1, sc1, vk2, sc2) => vk1 = vk2 && (!sc1 || !sc2 || sc1 = sc2)

SaveFromGui(*) {
    global CFG
    CaptureCancel()
    if (err := ValidateSettings(DRAFT)) {
        UI.gui.Opt("+OwnDialogs")
        MsgBox(err, APP.short, "Icon!")
        RefreshSettings()
        return
    }
    hidingIcon := CFG.trayIcon && !DRAFT.trayIcon
    CFG := CloneSettings(DRAFT)
    try WriteSettings(SETTINGS_PATH, CFG)
    catch as e {
        UI.gui.Opt("+OwnDialogs")
        MsgBox("The settings are applied, but they couldn't be saved to:`n" SETTINGS_PATH "`n`n" e.Message, APP.short, "Icon!")
    }
    ApplySettings()
    ApplyAppTheme(CFG.theme)
    ScheduleUpdateCheck()
    if (UI.autostartOn != (FileExist(APP.lnk) != ""))
        SetAutostart(UI.autostartOn)
    UpdateTray()
    CloseSettings()
    if hidingIcon
        GlassToast("The tray icon is hidden", "To open the settings, start the app again", "info", 7000)
    else
        GlassToast("Settings saved", Summary(), "ok", 2500)
}

CloseSettings(*) {
    CaptureCancel()
    DestroySettings()
}

DestroySettings() {
    if !UI.gui
        return
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

; Rebuilds the window with the draft's theme, at the same place
RebuildSettings() {
    if !UI.gui
        return
    WinGetPos(&wx, &wy, , , UI.gui.Hwnd)
    autostartOn := UI.autostartOn
    CaptureCancel()
    DestroySettings()
    BuildSettings(autostartOn, wx, wy)
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

; Window background: the rounded cards on the window color
RenderBackground(wL, hL, cards) {
    th := UI.th, k := UI.k
    cv := Canvas(wL, hL, th.win)
    for c in cards {
        x := Round(c.x * k), y := Round(c.y * k), cw := Round(c.w * k), ch := Round(c.h * k)
        FillPathFree(cv.g, GT_RoundPath(x, y, cw, ch, 8 * k), Argb(th.card))
        StrokePathFree(cv.g, GT_RoundPath(x + 0.5, y + 0.5, cw - 1, ch - 1, 8 * k), Argb(th.border), 1)
    }
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
