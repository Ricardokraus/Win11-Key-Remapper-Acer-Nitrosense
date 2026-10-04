<#
.SYNOPSIS
    Runs the logic tests without installing the keyboard hook.

.DESCRIPTION
    Builds a patched copy of src\Win11KeyRemapper.ahk in %TEMP% where startup
    is removed and everything with side effects (SendInput, Run, lock-key
    toggles, toasts, message boxes) is replaced by recording stubs. Then it
    appends tests\tests.ahk, which feeds fake key events straight into the
    hook procedure and drives a hidden settings window.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
    powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Ahk C:\ahk\AutoHotkey64.exe
#>
param(
    [string]$Ahk = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

if (-not $Ahk) {
    $candidates = @("$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
                    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe")
    $Ahk = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Ahk) { throw 'AutoHotkey v2 not found. Pass -Ahk <path to AutoHotkey64.exe>.' }
}

$work = Join-Path ([IO.Path]::GetTempPath()) 'Win11KeyRemapper-tests'
New-Item -ItemType Directory -Force (Join-Path $work 'src\lib') | Out-Null
Copy-Item (Join-Path $root 'src\lib\GlassToast.ahk') (Join-Path $work 'src\lib\GlassToast.ahk') -Force
Copy-Item (Join-Path $root 'settings.example.ini') (Join-Path $work 'settings.example.ini') -Force

$code = [IO.File]::ReadAllText((Join-Path $root 'src\Win11KeyRemapper.ahk'))

# Every patch must apply: a missed one could send real keys from the tests
$patches = [ordered]@{
    '^Main\(\)\s*$'                                 = '; (test) Main() removed'
    'g\.Show\("AutoSize"\)'                         = 'g.Show("AutoSize Hide")'
    'SetTimer\(RunQueue, -1\)'                      = '; (test) RunQueue is not scheduled'
    '\bGlassToast\('                                = 'TestToast('
    '\bMsgBox\('                                    = 'TestToast('
    '\bSendInput\('                                 = 'TestSend('
    '\bRun\('                                       = 'TestRun('
    '\bSet(NumLock|CapsLock|ScrollLock)State\('     = 'TestLock('
}
foreach ($p in $patches.GetEnumerator()) {
    if (-not [regex]::IsMatch($code, $p.Key, 'Multiline')) { throw "Test patch no longer applies: $($p.Key)" }
    $code = [regex]::Replace($code, $p.Key, $p.Value, 'Multiline')
}
$code += "`r`n" + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tests.ahk'))
$script = Join-Path $work 'src\test.ahk'
[IO.File]::WriteAllText($script, $code, (New-Object Text.UTF8Encoding $true))

$outFile = Join-Path $work 'stdout.txt'
$errFile = Join-Path $work 'stderr.txt'
$p = Start-Process -FilePath $Ahk -ArgumentList '/ErrorStdOut', "`"$script`"" -Wait -PassThru -NoNewWindow `
                   -RedirectStandardOutput $outFile -RedirectStandardError $errFile
Get-Content $outFile -Encoding UTF8
Get-Content $errFile -Encoding UTF8
if ($p.ExitCode -ne 0) {
    Write-Host "Tests failed (exit code $($p.ExitCode))"
    exit 1
}
