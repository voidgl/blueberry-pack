# Blueberry Minecraft - Windows installer
# Sets up (or repairs) the "Blueberry" instance in Prism Launcher.
# Mods download automatically on every launch via packwiz, so this only ever needs running once.
#
# Run it any of these ways:
#   - double-click Install-Blueberry-Windows.bat (this script is embedded in it)
#   - PowerShell:  irm https://voidgl.github.io/blueberry-pack/install/windows.ps1 | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is ~10x slower with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BB = @{
    Name         = 'Blueberry'
    Server       = 'sale-existed.gl.joinmc.link'
    PackUrl      = 'https://voidgl.github.io/blueberry-pack/pack.toml'
    IconUrl      = 'https://voidgl.github.io/blueberry-pack/install/icon.png'
    BootstrapUrl = 'https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/v0.0.3/packwiz-installer-bootstrap.jar'
    Minecraft    = '1.21.10'
    Fabric       = '0.18.4'
    # servers.dat with one entry: Blueberry -> Server, resource packs auto-accepted
    ServersDat   = 'CgAACQAHc2VydmVycwoAAAABCAACaXAAG3NhbGUtZXhpc3RlZC5nbC5qb2lubWMubGluawgABG5hbWUACUJsdWViZXJyeQEADmFjY2VwdFRleHR1cmVzAQAA'
}

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Info($m) { Write-Host "    $m" -ForegroundColor Gray }
function Warn($m) { Write-Host "    [!] $m" -ForegroundColor Yellow }

function Write-Utf8($path, $text) {
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Find-PrismExe {
    $running = Get-Process -Name prismlauncher -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($running -and $running.Path) { return $running.Path }
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\PrismLauncher\prismlauncher.exe",
        "$env:ProgramFiles\PrismLauncher\prismlauncher.exe",
        "${env:ProgramFiles(x86)}\PrismLauncher\prismlauncher.exe",
        "$env:USERPROFILE\scoop\apps\prismlauncher\current\prismlauncher.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    # Installed somewhere custom - ask the uninstall registry
    $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $entry = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Prism Launcher*' -and $_.InstallLocation } | Select-Object -First 1
    if ($entry) {
        $exe = Join-Path $entry.InstallLocation 'prismlauncher.exe'
        if (Test-Path $exe) { return $exe }
    }
    return $null
}

function Install-Prism {
    Info 'Prism Launcher not found - downloading it...'
    $release = Invoke-RestMethod 'https://api.github.com/repos/PrismLauncher/PrismLauncher/releases/latest'
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'MSVC-arm64-Setup' } else { 'MSVC-Setup' }
    $asset = $release.assets | Where-Object { $_.name -like "*Windows-$arch-*.exe" } | Select-Object -First 1
    if (-not $asset) { throw 'Could not find the Prism Launcher installer on GitHub.' }
    $setup = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $setup -UseBasicParsing
    Info 'Installing Prism Launcher...'
    Start-Process $setup -ArgumentList '/S' -Wait
    Remove-Item $setup -ErrorAction SilentlyContinue
}

# Prism keeps its data in %APPDATA%\PrismLauncher, unless it's a portable install
function Find-PrismData($exe) {
    if ($exe) {
        $dir = Split-Path $exe
        if (Test-Path (Join-Path $dir 'UserData')) { return (Join-Path $dir 'UserData') }
        if (Test-Path (Join-Path $dir 'portable.txt')) { return $dir }
        if ($exe -like '*\scoop\apps\*') {
            $persist = "$env:USERPROFILE\scoop\persist\prismlauncher"
            if (Test-Path $persist) { return $persist }
        }
    }
    return "$env:APPDATA\PrismLauncher"
}

# Respect a custom instance folder set in Prism's settings
function Find-InstancesDir($data) {
    $dir = Join-Path $data 'instances'
    $cfg = Join-Path $data 'prismlauncher.cfg'
    if (Test-Path $cfg) {
        $line = Get-Content $cfg | Where-Object { $_ -match '^InstanceDir=' } | Select-Object -First 1
        if ($line) {
            $val = ($line -replace '^InstanceDir=', '').Trim('"') -replace '\\\\', '\'
            if ($val) {
                if ([IO.Path]::IsPathRooted($val)) { $dir = $val } else { $dir = Join-Path $data $val }
            }
        }
    }
    return $dir
}

function Get-MemoryMB {
    try {
        $gb = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        if ($gb -ge 15) { return 6144 }
        if ($gb -ge 11) { return 5120 }
    } catch {}
    return 4096
}

function Main {
    Write-Host ''
    Write-Host '  ==========================================' -ForegroundColor Magenta
    Write-Host '        Blueberry - Minecraft installer'      -ForegroundColor Magenta
    Write-Host '  ==========================================' -ForegroundColor Magenta
    Write-Host '  Sets up the Blueberry modpack in Prism Launcher'
    Write-Host '  with the server already in your list.'

    # --- 1. Prism ---------------------------------------------------------
    Step 'Looking for Prism Launcher'
    $exe = Find-PrismExe
    if ($exe) { Ok "Found it: $exe" } else {
        Install-Prism
        $exe = Find-PrismExe
        if ($exe) { Ok 'Prism Launcher installed' } else { Warn 'Installed, but could not locate it - open Prism from the Start menu afterwards.' }
    }

    $proc = Get-Process -Name prismlauncher -ErrorAction SilentlyContinue
    if ($proc) {
        Info 'Closing Prism so it picks up the new instance...'
        $proc | ForEach-Object { [void]$_.CloseMainWindow() }
        Start-Sleep -Seconds 3
        Get-Process -Name prismlauncher -ErrorAction SilentlyContinue | Stop-Process -Force
    }

    # --- 2. Instance --------------------------------------------------------
    Step 'Setting up the Blueberry instance'
    $data = Find-PrismData $exe
    $instances = Find-InstancesDir $data
    $inst = Join-Path $instances $BB.Name
    $fresh = -not (Test-Path $inst)
    if ($fresh) { Info "Creating $inst" } else { Info 'Existing Blueberry instance found - updating it (your worlds, settings and screenshots are kept).' }

    # Prism uses "minecraft" for newer instances, ".minecraft" for older ones - keep whichever exists
    $game = Join-Path $inst '.minecraft'
    if (-not (Test-Path $game) -and (Test-Path (Join-Path $inst 'minecraft'))) { $game = Join-Path $inst 'minecraft' }
    New-Item -ItemType Directory -Force -Path $game | Out-Null

    $mem = Get-MemoryMB
    Write-Utf8 (Join-Path $inst 'mmc-pack.json') @"
{
    "components": [
        { "uid": "net.minecraft", "version": "$($BB.Minecraft)", "important": true },
        { "uid": "net.fabricmc.intermediary", "version": "$($BB.Minecraft)", "dependencyOnly": true },
        { "uid": "net.fabricmc.fabric-loader", "version": "$($BB.Fabric)" }
    ],
    "formatVersion": 1
}
"@
    # $INST_JAVA is quoted so Java paths with spaces work
    Write-Utf8 (Join-Path $inst 'instance.cfg') @"
[General]
ConfigVersion=1.2
InstanceType=OneSix
name=$($BB.Name)
iconKey=blueberry
notes=Seth's modded survival server - Fabric $($BB.Minecraft)\nMods update automatically every time you launch.
AutomaticJava=true
OverrideMemory=true
MinMemAlloc=1024
MaxMemAlloc=$mem
OverrideCommands=true
PreLaunchCommand="\"`$INST_JAVA\" -jar packwiz-installer-bootstrap.jar $($BB.PackUrl)"
"@
    Ok "Instance config written ($([math]::Round($mem/1024)) GB RAM for the game)"

    Info 'Downloading the mod updater...'
    Invoke-WebRequest $BB.BootstrapUrl -OutFile (Join-Path $game 'packwiz-installer-bootstrap.jar') -UseBasicParsing
    Ok 'Mod updater ready'

    $servers = Join-Path $game 'servers.dat'
    $hasServer = (Test-Path $servers) -and ([IO.File]::ReadAllText($servers, [Text.Encoding]::ASCII) -like "*$($BB.Server)*")
    if (-not $hasServer) {
        if (Test-Path $servers) { Copy-Item $servers "$servers.bak" -Force }
        [IO.File]::WriteAllBytes($servers, [Convert]::FromBase64String($BB.ServersDat))
    }
    Ok 'Blueberry server added to your server list'

    try {
        $icons = Join-Path $data 'icons'
        New-Item -ItemType Directory -Force -Path $icons | Out-Null
        Invoke-WebRequest $BB.IconUrl -OutFile (Join-Path $icons 'blueberry.png') -UseBasicParsing
    } catch { Info '(Skipped the instance icon - not important)' }

    # --- 3. Done ------------------------------------------------------------
    Write-Host ''
    Write-Host '  ==========================================' -ForegroundColor Green
    Write-Host '        All set!'                             -ForegroundColor Green
    Write-Host '  ==========================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Prism is opening and starting Blueberry now.'
    Write-Host '  First launch downloads ~110 mods - give it a few minutes.' -ForegroundColor Yellow
    Write-Host '  Then: Multiplayer -> Blueberry -> Join.'
    Write-Host '  (If the server is asleep it takes ~1 minute to wake up - just rejoin.)' -ForegroundColor Gray
    Write-Host ''
    Write-Host "  Server: $($BB.Server)" -ForegroundColor Yellow
    Write-Host '  Problems? Screenshot this window and send it to Seth.' -ForegroundColor Gray

    if ($exe) { Start-Process $exe -ArgumentList '--launch', $BB.Name }
}

try {
    Main
} catch {
    Write-Host ''
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  Screenshot this window and send it to Seth.' -ForegroundColor Yellow
}
