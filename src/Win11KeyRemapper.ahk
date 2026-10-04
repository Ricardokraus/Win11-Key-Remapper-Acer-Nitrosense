#Requires AutoHotkey v2.0
#SingleInstance Force
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
      , lnk: A_Startup "\Windows 11 Key Remapper.lnk"
      , dataDir: A_AppData "\Win11KeyRemapper"}

; A key-down that arrives this soon after the previous one, without a key-up
; in between, is keyboard auto-repeat. Must exceed the longest Windows repeat
; delay (1 s), otherwise holding the key would toggle twice.
REPEAT_MS := 1500

MODES       := ["NumLock", "CapsLock", "ScrollLock", "Key", "Disable", "None"]
MODE_LABELS := ["Toggle Num Lock", "Toggle Caps Lock", "Toggle Scroll Lock"
              , "Press another key / shortcut", "Disable the key", "Off (keep original behavior)"]

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

LISTEN_TEXT := "Press the key or shortcut now (click again to cancel)"
DETECT_LABEL := Map("source", "Detect key…", "target", "Detect…", "launch", "Detect shortcut…")

INI_HEADER := "
(
; Windows 11 Key Remapper - settings
; Change them from the tray icon > Settings..., or edit this file and restart the app.
; VK = virtual-key code, SC = scan code (hex). The Detect buttons show them for any key.
; Mode: NumLock | CapsLock | ScrollLock | Key | Disable | None
; Modifiers (comma-separated): LCtrl RCtrl LAlt RAlt LShift RShift LWin RWin
; LaunchPath: auto, a path to an .exe or .lnk, or shell:AppsFolder\<AppID>

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

Main()

; ============================================================================
; Startup / exit
; ============================================================================

Main() {
    global SETTINGS_PATH, CFG, POWER_NOTIFY
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
    } else if CFG.showToast
        SetTimer(StatusToast, -2000)        ; give the desktop time to paint
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
          , showToast: true}
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
          , mode: IniMode(path, d.mode)
          , targetMods: ParseMods(IniStr(path, "Remap", "TargetMods", JoinMods(d.targetMods)))
          , targetVK: IniHex(path, "Remap", "TargetVK", d.targetVK)
          , targetSC: IniHex(path, "Remap", "TargetSC", d.targetSC)
          , launchEnabled: IniBool(path, "Launcher", "LaunchEnabled", d.launchEnabled)
          , launchMods: ParseMods(IniStr(path, "Launcher", "LaunchMods", JoinMods(d.launchMods)))
          , launchVK: IniHex(path, "Launcher", "LaunchVK", d.launchVK)
          , launchSC: IniHex(path, "Launcher", "LaunchSC", d.launchSC)
          , launchAnySide: IniBool(path, "Launcher", "LaunchAnySide", d.launchAnySide)
          , launchPath: launchPath
          , showToast: IniBool(path, "General", "ShowToast", d.showToast)}
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

IniMode(path, def) {
    v := IniStr(path, "Remap", "Mode", def)
    for m in MODES
        if (v = m)
            return m
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

ComboLabel(mods, vk, sc, anySide := false) {
    out := "", seen := Map()
    for name in mods {
        label := anySide ? MOD_FAMILY[name] : MOD_LABEL[name]
        if !seen.Has(label)
            out .= label " + ", seen[label] := true
    }
    return out KeyLabel(vk, sc)
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
    tray.Add("Open settings folder", (*) => OpenSettingsFolder())
    tray.Add("About / GitHub", (*) => ShowAbout())
    tray.Add()
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Settings…"
    tray.ClickCount := 2
    UpdateTray()
}

UpdateTray() {
    try {
        PAUSED ? A_TrayMenu.Check("Pause remapping") : A_TrayMenu.Uncheck("Pause remapping")
        FileExist(APP.lnk) ? A_TrayMenu.Check("Start with Windows") : A_TrayMenu.Uncheck("Start with Windows")
    }
    A_IconTip := SubStr(APP.name (PAUSED ? " (paused)" : "") "`n" Summary(), 1, 127)
}

TogglePause() {
    global PAUSED
    ReleasePresses()
    PAUSED := !PAUSED
    UpdateTray()
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
    if UI.gui
        UI.autostart.Value := on
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

ShowSettings(firstRun := false) {
    global DRAFT
    if UI.gui {
        UI.gui.Show()
        return
    }
    DRAFT := CloneSettings(CFG)
    g := Gui("-MinimizeBox -MaximizeBox", "Settings - " APP.name)
    g.BackColor := "FFFFFF"
    g.MarginX := 24, g.MarginY := 18
    g.SetFont("s10 c1F1F1F", "Segoe UI")
    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)
    UI.gui := g

    Section(g, "Key to remap", true)
    UI.srcEdit := g.AddEdit("xm y+6 w356 r1 ReadOnly -TabStop")
    UI.srcBtn := g.AddButton("x+8 yp-1 w116 hp+2", DETECT_LABEL["source"])
    UI.matchSC := g.AddCheckbox("xm y+10 w480", "Match the exact scan code (recommended for vendor keys like NitroSense)")

    Section(g, "What it should do")
    UI.mode := g.AddDropDownList("xm y+6 w480 AltSubmit", MODE_LABELS)
    UI.targetLbl := g.AddText("xm y+12", "Key or shortcut to press instead:")
    UI.targetEdit := g.AddEdit("xm y+4 w356 r1 ReadOnly -TabStop")
    UI.targetBtn := g.AddButton("x+8 yp-1 w116 hp+2", DETECT_LABEL["target"])

    Section(g, "Shortcut to open NitroSense (optional)")
    UI.launchOn := g.AddCheckbox("xm y+6", "Enable")
    UI.launchEdit := g.AddEdit("xm y+8 w356 r1 ReadOnly -TabStop")
    UI.launchBtn := g.AddButton("x+8 yp-1 w116 hp+2", DETECT_LABEL["launch"])
    UI.anySide := g.AddCheckbox("xm y+10 w480", "Either left or right modifiers (Ctrl, Alt, Shift, Win)")
    UI.pathLbl := g.AddText("xm y+12", "App to open:")
    UI.path := g.AddEdit("xm y+4 w290 r1")
    UI.browse := g.AddButton("x+8 yp-1 w106 hp+2", "Browse…")
    UI.auto := g.AddButton("x+8 yp w68 hp", "Auto")
    g.SetFont("s9")
    UI.hint := g.AddText("xm y+6 w480 0x8080")             ; SS_PATHELLIPSIS | SS_NOPREFIX
    g.SetFont("s10")

    Section(g, "General")
    UI.autostart := g.AddCheckbox("xm y+6", "Start with Windows")
    UI.toast := g.AddCheckbox("xm y+8", "Show a notification at startup and when unlocking")

    g.AddText("xm y+20 w480 h1 0x10")                       ; SS_ETCHEDHORZ separator
    UI.reset := g.AddButton("xm y+14 w130", "Reset defaults")
    UI.cancel := g.AddButton("x296 yp w100", "Cancel")
    UI.save := g.AddButton("x+8 yp w100 Default", "Save")

    UI.srcBtn.OnEvent("Click", (*) => CaptureToggle("source"))
    UI.targetBtn.OnEvent("Click", (*) => CaptureToggle("target"))
    UI.launchBtn.OnEvent("Click", (*) => CaptureToggle("launch"))
    UI.matchSC.OnEvent("Click", (ctl, *) => DRAFT.matchSC := ctl.Value)
    UI.mode.OnEvent("Change", OnModeChange)
    UI.launchOn.OnEvent("Click", OnLaunchToggle)
    UI.anySide.OnEvent("Click", (ctl, *) => (DRAFT.launchAnySide := ctl.Value, RefreshSettings()))
    UI.path.OnEvent("Change", OnPathChange)
    UI.browse.OnEvent("Click", BrowseApp)
    UI.auto.OnEvent("Click", (*) => (UI.path.Value := "", OnPathChange()))
    UI.toast.OnEvent("Click", (ctl, *) => DRAFT.showToast := ctl.Value)
    UI.reset.OnEvent("Click", ResetDraft)
    UI.cancel.OnEvent("Click", CloseSettings)
    UI.save.OnEvent("Click", SaveFromGui)

    SendMessage(0x1501, true, StrPtr("Auto-detect NitroSense"), UI.path)   ; EM_SETCUEBANNER
    UI.autostart.Value := firstRun || FileExist(APP.lnk) != ""
    RefreshSettings()
    g.Show("AutoSize")
    if !NS.checked
        SetTimer(DetectForHint, -150)       ; after the window is on screen
}

Section(g, title, first := false) {
    g.SetFont("s11 w600 c1A7F37")
    g.AddText(first ? "xm" : "xm y+20", title)
    g.SetFont("s10 w400 c1F1F1F")
}

RefreshSettings() {
    if !UI.gui
        return
    d := DRAFT
    listening := CAP.active ? CAP.target : ""
    isKey := d.mode = "Key"

    UI.srcEdit.Value := listening = "source" ? LISTEN_TEXT : FieldText(d.sourceVK, d.sourceSC)
    UI.matchSC.Value := d.matchSC
    UI.mode.Value := ModeIndex(d.mode)
    UI.targetEdit.Value := listening = "target" ? LISTEN_TEXT : FieldText(d.targetVK, d.targetSC, d.targetMods)
    for ctl in [UI.targetLbl, UI.targetEdit, UI.targetBtn]
        ctl.Enabled := isKey

    UI.launchOn.Value := d.launchEnabled
    UI.launchEdit.Value := listening = "launch" ? LISTEN_TEXT : FieldText(d.launchVK, d.launchSC, d.launchMods, d.launchAnySide)
    UI.anySide.Value := d.launchAnySide
    for ctl in [UI.launchEdit, UI.launchBtn, UI.anySide, UI.pathLbl, UI.path, UI.browse, UI.auto, UI.hint]
        ctl.Enabled := d.launchEnabled
    pathText := d.launchPath = "auto" ? "" : d.launchPath
    if (UI.path.Value != pathText)
        UI.path.Value := pathText
    UI.toast.Value := d.showToast

    UI.srcBtn.Text := listening = "source" ? "Listening…" : DETECT_LABEL["source"]
    UI.targetBtn.Text := listening = "target" ? "Listening…" : DETECT_LABEL["target"]
    UI.launchBtn.Text := listening = "launch" ? "Listening…" : DETECT_LABEL["launch"]
    UpdateHint()
}

ModeIndex(mode) {
    for i, m in MODES
        if (m = mode)
            return i
    return 1
}

UpdateHint() {
    if !UI.gui
        return
    p := DRAFT.launchPath, warn := false
    if (p = "auto") {
        if !NS.checked
            text := "Looking for NitroSense…"
        else if (NS.target != "")
            text := "Auto-detect found: " (NS.label != "" ? NS.label : NS.target)
        else
            text := "Auto-detect: NitroSense not found — use Browse…", warn := true
    } else if (SubStr(p, 1, 6) = "shell:")
        text := "Opens an app from the Apps folder"
    else if FileExist(p) {
        SplitPath(p, &file)
        text := "Opens " file
    } else
        text := "File not found — check the path or use Browse…", warn := true
    UI.hint.Value := text
    UI.hint.SetFont(warn ? "cC42B1C" : "c6E6E73")
}

DetectForHint() {
    DetectNitroSense()
    UpdateHint()
}

OnModeChange(ctl, *) {
    DRAFT.mode := MODES[ctl.Value]
    if (CAP.active && CAP.target = "target" && DRAFT.mode != "Key")
        CaptureCancel()
    RefreshSettings()
}

OnLaunchToggle(ctl, *) {
    DRAFT.launchEnabled := ctl.Value
    if (CAP.active && CAP.target = "launch" && !DRAFT.launchEnabled)
        CaptureCancel()
    RefreshSettings()
}

OnPathChange(*) {
    v := Trim(UI.path.Value)
    DRAFT.launchPath := (v = "" || v = "auto") ? "auto" : v
    UpdateHint()
}

BrowseApp(*) {
    UI.gui.Opt("+OwnDialogs")
    file := FileSelect(35, , "Choose the app to open", "Programs (*.exe; *.lnk)")   ; 1+2+32: must exist, keep .lnk
    if (file != "") {
        UI.path.Value := file
        OnPathChange()
    }
}

ResetDraft(*) {
    global DRAFT
    CaptureCancel()
    DRAFT := DefaultSettings()
    RefreshSettings()
}

ValidateSettings(d) {
    if (d.mode != "None" && !d.sourceVK)
        return "Choose the key to remap first (Detect key…)."
    if (d.mode = "Key" && !d.targetVK)
        return "Choose the key or shortcut to press instead (Detect…), or pick another action."
    if d.launchEnabled {
        if !d.launchVK
            return "Choose the shortcut that opens NitroSense (Detect shortcut…), or turn it off."
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
    CFG := CloneSettings(DRAFT)
    try WriteSettings(SETTINGS_PATH, CFG)
    catch as e {
        UI.gui.Opt("+OwnDialogs")
        MsgBox("The settings are applied, but they couldn't be saved to:`n" SETTINGS_PATH "`n`n" e.Message, APP.short, "Icon!")
    }
    ApplySettings()
    if (UI.autostart.Value != (FileExist(APP.lnk) != ""))
        SetAutostart(UI.autostart.Value)
    UpdateTray()
    CloseSettings()
    GlassToast("Settings saved", Summary(), "ok", 2500)
}

CloseSettings(*) {
    CaptureCancel()
    if UI.gui {
        g := UI.gui
        UI.gui := 0
        g.Destroy()
    }
}
