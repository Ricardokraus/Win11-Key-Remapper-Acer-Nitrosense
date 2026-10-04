<#
.SYNOPSIS
    Builds dist\Win11KeyRemapper.exe locally, the same way GitHub Actions does.

.DESCRIPTION
    Downloads AutoHotkey v2 and Ahk2Exe from their official GitHub releases into
    %LOCALAPPDATA%\Win11KeyRemapper-build (once), checks the syntax and compiles.
    Nothing is installed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cache = Join-Path $env:LOCALAPPDATA 'Win11KeyRemapper-build'
$ahk = Join-Path $cache 'ahk\AutoHotkey64.exe'
$ahk2exe = Join-Path $cache 'ahk2exe\Ahk2Exe.exe'

function Get-ReleaseZip([string]$repo, [string]$pattern, [string]$dest, [string]$tagPrefix = '') {
    $releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=30" -Headers @{ 'User-Agent' = 'Win11KeyRemapper-build' }
    $release = $releases | Where-Object { -not $_.prerelease -and -not $_.draft -and $_.tag_name -like "$tagPrefix*" } | Select-Object -First 1
    $asset = $release.assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
    if (-not $asset) { throw "No $pattern in $repo releases" }
    Write-Host "Downloading $($asset.name)"
    $zip = Join-Path $cache $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
    Expand-Archive $zip $dest -Force
}

New-Item -ItemType Directory -Force $cache | Out-Null
if (-not (Test-Path $ahk))     { Get-ReleaseZip 'AutoHotkey/AutoHotkey' 'AutoHotkey_*.zip' (Join-Path $cache 'ahk') 'v2.' }
if (-not (Test-Path $ahk2exe)) { Get-ReleaseZip 'AutoHotkey/Ahk2Exe' 'Ahk2Exe*.zip' (Join-Path $cache 'ahk2exe') }

$src = Join-Path $root 'src\Win11KeyRemapper.ahk'
$p = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/Validate', "`"$src`"" -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { throw 'Syntax check failed' }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$exe = Join-Path $dist 'Win11KeyRemapper.exe'
$p = Start-Process $ahk2exe -Wait -PassThru -NoNewWindow -ArgumentList `
       '/in', "`"$src`"", '/out', "`"$exe`"", '/base', "`"$ahk`"", '/silent'
if ($p.ExitCode -ne 0 -or -not (Test-Path $exe)) { throw 'Compile failed' }
Write-Host "Built $exe"
