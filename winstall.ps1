<#
.SYNOPSIS
    PhValheim Client - Windows installer.

.DESCRIPTION
    Per-user install of the PhValheim Client, the Windows counterpart to
    macinstall.sh.

    WHY THIS EXISTS, AND WHY IT IS NOT JUST "THE MSI BUT SMALLER":

    Microsoft Defender SmartScreen's application-reputation check is gated on
    the Mark of the Web -- the Zone.Identifier alternate data stream that
    browsers attach to every download via IAttachmentExecute. Our .msi is
    downloaded in a browser, so it carries MOTW, so every user gets "Windows
    protected your PC" until the file hash earns reputation. Microsoft's own
    guidance is "several weeks and hundreds of clean installs from a wide
    audience" PER FILE HASH, and every release resets to zero. Our best release
    ever (2.0.12) took six months to reach 191 downloads. That threshold is
    never going to be met, so the warning is permanent.

    Invoke-WebRequest does not go through IAttachmentExecute and therefore does
    not set MOTW. A payload fetched by this script is unmarked, so the
    reputation check never fires. This is the same mechanism behind rustup,
    Scoop, Chocolatey and every other `irm ... | iex` installer.

    Installing per-user under %APPDATA% and HKCU also means NO elevation, which
    removes the UAC "Unknown Publisher" prompt as well.

    MIGRATION: an existing .msi install is REMOVED and replaced, not installed
    alongside. Both use the same folder and Windows Installer keeps ownership of
    those files, so coexistence is not a stable state. The removal is the one
    step that needs administrator rights, it happens once, and the UAC prompt
    comes from Microsoft-signed msiexec.exe rather than from our unsigned
    package. After that, updates and removal need no elevation at all.

    This does NOT help with antivirus heuristics (see issue #7) and does NOT
    help on machines with Smart App Control enabled -- SAC checks every
    executable regardless of MOTW. Signing is still the answer to both; this
    script is the answer to SmartScreen.

.PARAMETER Action
    install (default) | uninstall | diags

.PARAMETER Version
    Release tag to install. Defaults to the latest GitHub release.
    Tags are bare numeric: 2.0.13, never v2.0.13.

.PARAMETER Msi
    Install from an .msi already on disk instead of downloading one. The
    local-testing hook, mirroring macinstall.sh's PHVALHEIM_TARBALL. Everything
    after the extract is the code the real installer runs, so a test exercises
    the shipped path rather than a test-only reimplementation that can drift.

.PARAMETER SkipMsiRemoval
    Do not remove a detected MSI install before installing. Leaves two installs
    claiming the same folder, which is not a state to ship anyone -- this exists
    for testing the conflict, not for use.

.EXAMPLE
    # From a file
    powershell -ExecutionPolicy Bypass -File winstall.ps1

.EXAMPLE
    # One-liner, no arguments
    irm https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/winstall.ps1 | iex

.EXAMPLE
    # One-liner WITH arguments. `iex` cannot take parameters, so the script has
    # to become a scriptblock first. This is the only form that works.
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/winstall.ps1))) uninstall
#>

# Justifications must be single string constants -- PSScriptAnalyzer refuses to
# load a suppression whose argument is a concatenation, and reports that refusal
# as a file-level error rather than as a problem with the attribute.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive installer; its console output is the product, not pipeline data.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Msi and SkipMsiRemoval are read by Invoke-Install via script scope, which PSSA does not track.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
    Justification = 'Invoke-Diags mirrors the diags subcommand name, which matches macinstall.sh.')]
[CmdletBinding()]
param(
    [ValidateSet('install', 'uninstall', 'diags')]
    [string] $Action = 'install',

    [string] $Version,
    [string] $Msi,
    [switch] $SkipMsiRemoval
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Invoke-WebRequest renders a progress bar by redrawing the host on every
# chunk, which on a 32 MB download costs more wall-clock than the transfer.
$ProgressPreference = 'SilentlyContinue'

# Windows PowerShell 5.1 still negotiates SSL3/TLS1.0 first on some builds and
# GitHub refuses those. Cheap insurance; harmless on PowerShell 7.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # Deliberately non-fatal. PowerShell 7 on a modern runtime manages this
    # itself and can reject the assignment; that is fine, the download still
    # negotiates TLS 1.2+. Only an actual transfer failure should stop us.
    Write-Verbose "Could not pin TLS 1.2: $($_.Exception.Message)"
}

# -- constants ----------------------------------------------------------------
# Every path and registry value below is lifted from builders/wxs/phvalheim-client.wxs.
# They are a contract with the SHIPPED 2.0.12/2.0.13 installs, not free choices:
# an existing install and a phvalheim:// link already point at these exact
# locations. Changing one silently breaks upgrades and the URL handler.

$GithubRepo  = 'brianmiller/phvalheim-client'
$ProductName = 'PhValheim Client'
$Publisher   = 'Phospher'
$ExeName     = 'phvalheim-client.exe'
$IcoName     = 'phvalheim-client.ico'

# %APPDATA%\PhValheim\phvalheim-client\ -- NOT Program Files. This is what the
# retired .vdproj shipped, what the .wxs reproduces, and what the registered
# phvalheim:// command line points at.
$InstallDir  = Join-Path $env:APPDATA 'PhValheim\phvalheim-client'
$InstallExe  = Join-Path $InstallDir $ExeName
$InstallIco  = Join-Path $InstallDir $IcoName
$Uninstaller = Join-Path $InstallDir 'uninstall.ps1'

# Per-user equivalents of the MSI's HKCR / machine-wide ARP writes. HKCR is a
# merged view of HKLM\Software\Classes and HKCU\Software\Classes; writing the
# HKCU side registers the scheme for this user with no elevation.
$ClassesKey = 'Software\Classes\phvalheim'
$ArpKey     = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\PhValheimClient'

function Write-Ok   { param([string] $m) Write-Host "  [OK]  $m" }
function Write-Warn { param([string] $m) Write-Host "  [!!]  $m" -ForegroundColor Yellow }
function Write-Fail { param([string] $m) Write-Host "  [XX]  $m" -ForegroundColor Red }

# -- MSI-install detection and migration --------------------------------------
# The .msi installs to the SAME %APPDATA% directory this script writes to, and
# Windows Installer still considers those files its own. Leaving both in place
# is not a stable state: repairing the MSI overwrites the script's payload, and
# uninstalling it deletes the payload while leaving the script's registry
# entries pointing at a binary that is gone. So an MSI install is migrated --
# removed first, then replaced -- rather than installed alongside.
function Get-MsiInstall {
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($sub in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            # Our own ARP key is not an MSI install.
            if ($sub.PSChildName -eq 'PhValheimClient') { continue }
            $props = Get-ItemProperty $sub.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $props) { continue }
            if (($props.PSObject.Properties.Name -contains 'DisplayName') -and
                ($props.DisplayName -eq $ProductName)) {

                $names = $props.PSObject.Properties.Name
                $uninstallString = if ($names -contains 'UninstallString') { $props.UninstallString } else { '' }

                # For a Windows Installer package the ARP subkey name IS the
                # ProductCode. Fall back to digging the GUID out of the
                # UninstallString for anything that does not follow that rule.
                $productCode = $null
                if ($sub.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') {
                    $productCode = $sub.PSChildName
                } elseif ($uninstallString -match '(\{[0-9A-Fa-f-]{36}\})') {
                    $productCode = $Matches[1]
                }

                return [pscustomobject]@{
                    Key             = $sub.PSChildName
                    ProductCode     = $productCode
                    UninstallString = $uninstallString
                    Version         = if ($names -contains 'DisplayVersion') { $props.DisplayVersion } else { 'unknown' }
                }
            }
        }
    }
    return $null
}

# Remove an MSI-managed install so the scripted one can take its place.
#
# This is the one step that needs elevation: the package is InstallScope
# perMachine, so msiexec has to run as administrator and Windows shows a UAC
# prompt. That prompt comes from msiexec.exe, a Microsoft-signed binary, so it
# is the ordinary blue "Windows Installer" dialog and not the yellow "Unknown
# Publisher" one the .msi itself produces. It happens once, on migration only.
function Remove-MsiInstall {
    # SupportsShouldProcess because this uninstalls software off the user's
    # machine. It also makes -WhatIf work, which is the safe way to rehearse a
    # migration on a box you care about.
    [CmdletBinding(SupportsShouldProcess)]
    param([psobject] $Existing)

    Write-Host ''
    Write-Host "  Found an MSI install (version $($Existing.Version))."
    Write-Host '  It has to come out before the scripted install goes in: both use the'
    Write-Host '  same folder, and Windows Installer would delete these files later.'
    Write-Host ''
    Write-Host '  Windows will ask for administrator permission to remove it.'
    Write-Host ''

    if (-not $Existing.ProductCode) {
        throw ("Could not determine the ProductCode for the existing install " +
               "(ARP key '$($Existing.Key)'). Remove it via Settings > Apps > Installed apps, then re-run.")
    }

    if (-not $PSCmdlet.ShouldProcess("$ProductName $($Existing.Version) ($($Existing.ProductCode))",
                                     'Uninstall the MSI-managed install')) {
        Write-Warn 'Skipped the MSI removal (-WhatIf). The install below would collide with it.'
        return
    }

    $log = Join-Path ([IO.Path]::GetTempPath()) 'phvalheim-msi-removal.log'
    try {
        $p = Start-Process -FilePath 'msiexec.exe' `
                           -ArgumentList @('/x', $Existing.ProductCode, '/qn', '/norestart', '/l*v', "`"$log`"") `
                           -Verb RunAs -Wait -PassThru
    } catch {
        # The usual cause is the user clicking No on the UAC prompt.
        throw ("Could not elevate to remove the MSI install: $($_.Exception.Message). " +
               "Nothing has been changed.")
    }

    # 3010 is success-but-a-reboot-is-pending. Not our problem here: nothing we
    # are about to write depends on the reboot happening.
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        $hint = switch ($p.ExitCode) {
            1602 { 'the removal was cancelled' }
            1603 { 'a fatal error during removal -- see the log' }
            default { "msiexec exit code $($p.ExitCode)" }
        }
        throw "Removing the MSI install failed ($hint). Log: $log"
    }

    # Do NOT trust the exit code alone. A silent uninstall that quietly did
    # nothing and one that worked look identical from here, and installing on
    # top of a surviving MSI is exactly the broken state this avoids.
    $still = Get-MsiInstall
    if ($still) {
        throw ("msiexec reported success but the MSI install is still registered " +
               "(version $($still.Version)). Remove it via Settings > Apps > Installed apps, then re-run. Log: $log")
    }

    Write-Ok "Removed the MSI install (was $($Existing.Version))."

    # The MSI owns HKCR\phvalheim, whose writable half is HKLM\Software\Classes.
    # Its removal takes the machine-wide scheme registration with it; the
    # per-user one this script writes next is what replaces it. User data lives
    # in the PARENT folder (%APPDATA%\PhValheim) and is deliberately untouched
    # by both the MSI's uninstall and this script.
}

# -- payload acquisition ------------------------------------------------------
function Get-LatestVersion {
    Write-Host 'Fetching latest release info...'
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$GithubRepo/releases/latest" `
                             -Headers @{ 'User-Agent' = 'phvalheim-winstall' }
    if (-not $rel.tag_name) {
        throw "Could not determine the latest release. Check https://github.com/$GithubRepo/releases"
    }
    return $rel.tag_name
}

# The only Windows asset a release publishes is the .msi, so that is what we
# fetch -- but we never RUN it. `msiexec /a` is an administrative install: it
# unpacks the embedded cab to a directory and touches neither the live system
# nor the installer database, and it needs no elevation. That keeps this script
# shipping the exact binary the MSI ships, with no second Windows build to
# publish and no chance of the two drifting apart.
function Expand-MsiPayload {
    param([string] $MsiPath, [string] $Destination)

    Write-Host 'Extracting...'

    # The log lives OUTSIDE $Destination on purpose. $Destination is the temp
    # directory the caller deletes in its finally block, so a log written there
    # is destroyed by the very failure it documents.
    $log = Join-Path ([IO.Path]::GetTempPath()) 'phvalheim-msi-extract.log'
    Remove-Item $log -ErrorAction SilentlyContinue

    # One argument STRING, not an array. Start-Process re-quotes array elements
    # that already contain quotes, which is how the same call elsewhere in this
    # file ended up mangled.
    $msiArgs = "/a `"$MsiPath`" /qn TARGETDIR=`"$Destination`" /l*v `"$log`""
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

    if ($p.ExitCode -ne 0) {
        # A 20-line tail is almost always Windows Installer's shutdown chatter,
        # not the fault. Pull the lines that actually name a failure.
        if (Test-Path $log) {
            $signal = Get-Content $log |
                      Select-String -Pattern 'return value 3', 'Error \d+', 'cannot|failed|denied|Invalid' |
                      Select-Object -Last 15
            if ($signal) {
                Write-Host '--- msiexec log, lines naming a failure ---'
                $signal | ForEach-Object { Write-Host "  $_" }
            }
            Write-Host ''
            Write-Host "  Full log kept at: $log"
        }
        throw "msiexec /a failed with exit code $($p.ExitCode)."
    }

    # Do not assume the layout. An administrative install reproduces the MSI's
    # Directory table under TARGETDIR, so the exe lands several levels deep, and
    # that depth is a property of the .wxs rather than of this script.
    $found = Get-ChildItem -Path $Destination -Filter $ExeName -Recurse -File -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if (-not $found) {
        throw "$ExeName was not found anywhere under the extracted MSI. The package layout changed."
    }
    return $found.DirectoryName
}

# -- install ------------------------------------------------------------------
# Place an already-extracted tree. Shared by the release path and the -Msi path
# so both install identically.
function Install-FromTree {
    param([string] $SourceDir, [string] $InstalledVersion, [string] $MigratedFrom = '')

    $srcExe = Join-Path $SourceDir $ExeName
    if (-not (Test-Path $srcExe)) { throw "No $ExeName in $SourceDir" }

    Write-Host "Installing to $InstallDir..."
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    # A running client holds a lock on its own exe and Copy-Item's failure here
    # is an opaque "being used by another process". Name the actual problem.
    $running = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ExeName)) -ErrorAction SilentlyContinue
    if ($running) {
        throw "$ExeName is running (PID $($running.Id -join ', ')). Close it and re-run."
    }

    Copy-Item -Path $srcExe -Destination $InstallExe -Force

    $srcIco = Join-Path $SourceDir $IcoName
    if (Test-Path $srcIco) {
        Copy-Item -Path $srcIco -Destination $InstallIco -Force
    } else {
        Write-Warn "$IcoName not in the package; Add/Remove Programs will show a generic icon."
    }

    Register-UrlScheme
    Register-ArpEntry -InstalledVersion $InstalledVersion

    Write-Host ''
    if ($MigratedFrom) {
        Write-Ok "$ProductName $InstalledVersion installed (migrated from the $MigratedFrom MSI install)."
        Write-Host ''
        Write-Host '  The MSI install was removed. This one needs no administrator rights'
        Write-Host '  to update or remove, and updates will not trigger SmartScreen.'
    } else {
        Write-Ok "$ProductName $InstalledVersion installed."
    }
    Write-Host ''
    Write-Host "  Location : $InstallDir"
    Write-Host "  SHA256   : $((Get-FileHash -Path $InstallExe -Algorithm SHA256).Hash)"
    Write-Host ''
    Write-Host '  phvalheim:// links will now open this client.'
    Write-Host '  To remove it: Settings > Apps > Installed apps, or run:'
    Write-Host "    powershell -ExecutionPolicy Bypass -File `"$Uninstaller`""
    Write-Host ''
}

function Register-UrlScheme {
    Write-Host 'Registering the phvalheim:// URL scheme...'

    # The .NET registry API rather than New-ItemProperty, because the value type
    # of the DEFAULT value is load-bearing here and the cmdlets make it awkward
    # to set precisely.
    $base = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($ClassesKey)
    try {
        $base.SetValue('', $ProductName, [Microsoft.Win32.RegistryValueKind]::String)
        # Presence of this value -- not its content -- is what marks the key as
        # a protocol handler. It is deliberately empty.
        $base.SetValue('URL Protocol', '', [Microsoft.Win32.RegistryValueKind]::String)
    } finally { $base.Close() }

    $cmd = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$ClassesKey\shell\open\command")
    try {
        # REG_EXPAND_SZ, matching Type="expandable" in the .wxs. As a plain
        # REG_SZ, Windows hands the literal string "%appdata%\..." to
        # CreateProcess and the handler fails silently -- a phvalheim:// click
        # does nothing at all, with no error anywhere.
        $cmd.SetValue('',
                      "`"%appdata%\PhValheim\phvalheim-client\$ExeName`" `"%1`"",
                      [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally { $cmd.Close() }
}

function Register-ArpEntry {
    param([string] $InstalledVersion)

    # Written last: an Add/Remove Programs entry is a promise that the thing it
    # describes is on disk. Registering it before the copy means a failed
    # install leaves a row pointing at nothing.
    $sizeKb = [int]((Get-Item $InstallExe).Length / 1024)

    # The uninstaller is generated rather than being a copy of this script,
    # because the `irm | iex` path has no file to copy -- and an uninstaller
    # that has to reach the network to run is an uninstaller that fails when
    # you need it most. The duplication is deliberate and bounded: these are
    # the only three things install creates.
    $body = @"
# Generated by winstall.ps1 at install time. Removes everything the installer
# creates: the payload directory, the phvalheim:// scheme, and the ARP entry.
`$ErrorActionPreference = 'Stop'
Write-Host ''
Write-Host '=== $ProductName - Uninstall ==='
Write-Host ''
`$proc = Get-Process -Name '$([IO.Path]::GetFileNameWithoutExtension($ExeName))' -ErrorAction SilentlyContinue
if (`$proc) { Write-Host "  Stopping running client..."; `$proc | Stop-Process -Force }
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('$ClassesKey', `$false)
Write-Host '  Removed the phvalheim:// scheme.'
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('$ArpKey', `$false)
Write-Host '  Removed the Add/Remove Programs entry.'
# Self-deleting: this script lives inside the directory it is deleting, so a
# plain Remove-Item would fail on the open file handle. Hand the delete to a
# detached cmd that waits for this process to exit first. One argument string,
# not an array -- Start-Process re-quotes array elements and mangles the `&`.
Start-Process -FilePath 'cmd.exe' ``
    -ArgumentList '/c timeout /t 3 /nobreak >nul & rmdir /s /q "$InstallDir"' ``
    -WindowStyle Hidden
Write-Host '  Removing $InstallDir...'
Write-Host ''
Write-Host '  Done. $ProductName uninstalled.'
Write-Host ''
"@
    Set-Content -Path $Uninstaller -Value $body -Encoding UTF8

    $arp = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($ArpKey)
    try {
        $arp.SetValue('DisplayName',     $ProductName)
        $arp.SetValue('DisplayVersion',  $InstalledVersion)
        $arp.SetValue('Publisher',       $Publisher)
        $arp.SetValue('DisplayIcon',     $(if (Test-Path $InstallIco) { $InstallIco } else { $InstallExe }))
        $arp.SetValue('InstallLocation', $InstallDir)
        $arp.SetValue('URLInfoAbout',    "https://github.com/$GithubRepo")
        $arp.SetValue('Contact',         'posixone')
        $arp.SetValue('UninstallString',
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Uninstaller`"")
        $arp.SetValue('EstimatedSize',   $sizeKb, [Microsoft.Win32.RegistryValueKind]::DWord)
        # This install has no repair or modify path. Saying so stops Windows
        # offering buttons that would do nothing.
        $arp.SetValue('NoModify', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $arp.SetValue('NoRepair', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    } finally { $arp.Close() }
}

function Invoke-Install {
    Write-Host ''
    Write-Host "=== $ProductName - Windows Installer ==="
    Write-Host ''

    # Detected now, acted on later. Removing the MSI is the only destructive
    # step here, so it happens as late as possible -- after the payload is
    # downloaded and extracted. Doing it up front means a failed download
    # leaves the user with nothing, which is worse than the working MSI install
    # they started with.
    $existing = Get-MsiInstall

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("phvalheim-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        if ($Msi) {
            if (-not (Test-Path $Msi)) { throw "-Msi was given but is not a file: $Msi" }
            $msiPath  = (Resolve-Path $Msi).Path
            $resolved = 'local'
            Write-Host "Installing local package: $msiPath"
        } else {
            $resolved = if ($Version) { $Version } else { Get-LatestVersion }
            Write-Host "Version: $resolved"

            $asset = "phvalheim-client-$resolved-x86_64.msi"
            $url   = "https://github.com/$GithubRepo/releases/download/$resolved/$asset"
            $msiPath = Join-Path $tmp $asset

            Write-Host "Downloading $asset..."
            # Invoke-WebRequest, deliberately. It does not attach Mark of the
            # Web, which is the entire reason this script exists -- see the
            # header. Do not "improve" this into Start-BitsTransfer or a
            # browser hand-off; both mark the file and SmartScreen returns.
            Invoke-WebRequest -Uri $url -OutFile $msiPath -UseBasicParsing
        }

        $payloadDir = Expand-MsiPayload -MsiPath $msiPath -Destination $tmp

        # The payload is on disk and verified to contain the exe. Only now is
        # it safe to take the old install out. Both write the same directory,
        # so the MSI must go first or its uninstall deletes what we place next.
        $migrated = ''
        if ($existing) {
            if ($SkipMsiRemoval) {
                Write-Warn "Leaving the MSI install ($($existing.Version)) in place because -SkipMsiRemoval was given."
                Write-Warn 'Both will claim the same folder. A debugging option, not a supported state.'
            } else {
                Remove-MsiInstall -Existing $existing
                $migrated = $existing.Version
            }
        }

        Install-FromTree -SourceDir $payloadDir -InstalledVersion $resolved -MigratedFrom $migrated
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# -- uninstall ----------------------------------------------------------------
function Invoke-Uninstall {
    Write-Host ''
    Write-Host "=== $ProductName - Uninstall ==="
    Write-Host ''

    $proc = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ExeName)) -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host '  Stopping running client...'
        $proc | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    # DeleteSubKeyTree with throwOnMissingSubKey = $false, so uninstalling a
    # partial install is not itself an error.
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($ClassesKey, $false)
    Write-Ok 'Removed the phvalheim:// scheme.'

    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($ArpKey, $false)
    Write-Ok 'Removed the Add/Remove Programs entry.'

    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Ok "Removed $InstallDir"
    } else {
        Write-Ok "$InstallDir was already gone."
    }

    $msi = Get-MsiInstall
    if ($msi) {
        Write-Warn "An MSI-managed install is still present (version $($msi.Version))."
        Write-Warn 'Remove it via Settings > Apps > Installed apps.'
    }

    Write-Host ''
    Write-Host "  Done. $ProductName uninstalled."
    Write-Host ''
}

# -- diags --------------------------------------------------------------------
# The oracle. Every check below can FAIL -- none of them answer the same way
# whether the install worked or not. In particular the URL-scheme check asserts
# the value TYPE, because a REG_SZ there looks correct to every string
# comparison and still leaves phvalheim:// completely dead.
function Invoke-Diags {
    Write-Host ''
    Write-Host "=== $ProductName - Diagnostics ==="
    Write-Host ''

    Write-Host '-- Payload --'
    if (Test-Path $InstallExe) {
        $f = Get-Item $InstallExe
        Write-Ok "Client present: $InstallExe"
        Write-Ok "Size: $([int]($f.Length / 1MB)) MB"
        Write-Ok "SHA256: $((Get-FileHash -Path $InstallExe -Algorithm SHA256).Hash)"
    } else {
        Write-Fail "Client MISSING: $InstallExe"
    }
    if (Test-Path $InstallIco) { Write-Ok "Icon present: $InstallIco" }
    else { Write-Warn "Icon missing: $InstallIco" }
    Write-Host ''

    Write-Host '-- It actually runs --'
    if (Test-Path $InstallExe) {
        # Zero args is a no-side-effect path: Arguments.cs prints usage and
        # bails before touching Steam, the network or the filesystem. A static
        # "the file exists" check passes on a binary Windows refuses to launch.
        try {
            $out = & $InstallExe 2>&1 | Out-String
            if ($out -match 'No arguments passed') {
                Write-Ok 'Client executes and printed its usage text.'
            } else {
                Write-Fail "Client ran but printed something unexpected: $($out.Trim() -split "`n" | Select-Object -First 1)"
            }
        } catch {
            Write-Fail "Client could not be executed: $($_.Exception.Message)"
        }
    }
    Write-Host ''

    Write-Host '-- phvalheim:// registration --'
    $cmdKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$ClassesKey\shell\open\command")
    if ($null -eq $cmdKey) {
        Write-Fail "Not registered: HKCU\$ClassesKey\shell\open\command is absent."
    } else {
        try {
            $kind = $cmdKey.GetValueKind('')
            # GetValue expands REG_EXPAND_SZ by default; ask for the raw form so
            # we can see whether %appdata% actually survived as a variable.
            $raw  = $cmdKey.GetValue('', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $live = $cmdKey.GetValue('')

            if ($kind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) {
                Write-Ok 'Command value is REG_EXPAND_SZ (correct).'
            } else {
                Write-Fail "Command value is $kind, must be REG_EXPAND_SZ -- phvalheim:// links will silently do nothing."
            }
            Write-Ok "Raw:      $raw"
            Write-Ok "Expanded: $live"

            # The registration can be perfectly well-formed and point at a
            # binary that is not there.
            if ($live -match '^"([^"]+)"') {
                if (Test-Path $Matches[1]) { Write-Ok 'Registered target exists on disk.' }
                else { Write-Fail "Registered target does NOT exist: $($Matches[1])" }
            }
        } finally { $cmdKey.Close() }
    }

    $baseKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($ClassesKey)
    if ($null -ne $baseKey) {
        try {
            if ($baseKey.GetValueNames() -contains 'URL Protocol') {
                Write-Ok '"URL Protocol" marker present.'
            } else {
                Write-Fail '"URL Protocol" marker MISSING -- Windows will not treat phvalheim as a scheme.'
            }
        } finally { $baseKey.Close() }
    }
    Write-Host ''

    Write-Host '-- Add/Remove Programs --'
    $arp = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($ArpKey)
    if ($null -eq $arp) {
        Write-Warn 'No ARP entry for the script install.'
    } else {
        try {
            Write-Ok "DisplayName:    $($arp.GetValue('DisplayName'))"
            Write-Ok "DisplayVersion: $($arp.GetValue('DisplayVersion'))"
            $us = $arp.GetValue('UninstallString')
            Write-Ok "UninstallString: $us"
            if (Test-Path $Uninstaller) { Write-Ok "Uninstaller present: $Uninstaller" }
            else { Write-Fail "UninstallString points at a missing file: $Uninstaller" }
        } finally { $arp.Close() }
    }

    $msi = Get-MsiInstall
    if ($msi) {
        Write-Warn "MSI-managed install ALSO present: version $($msi.Version) ($($msi.Key))"
        Write-Warn 'Two installs claim the same folder. Re-run install to migrate off the MSI.'
    } else {
        Write-Ok 'No conflicting MSI install.'
    }
    Write-Host ''

    Write-Host '-- Steam / Valheim --'
    $steam = $null
    $sk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Valve\Steam')
    if ($null -ne $sk) {
        try { $steam = $sk.GetValue('SteamPath') } finally { $sk.Close() }
    }
    if ($steam) {
        Write-Ok "Steam: $steam"
        # Platform.cs reads exactly this key, so a miss here is the same miss
        # the client will have.
        $valheim = Join-Path ($steam -replace '/', '\') 'steamapps\common\Valheim\valheim.exe'
        if (Test-Path $valheim) { Write-Ok "Valheim: $valheim" }
        else { Write-Warn "Valheim not at the default library path ($valheim). A secondary library is fine." }
    } else {
        Write-Warn 'Steam not found at HKCU\Software\Valve\Steam -- the client reads this key.'
    }
    Write-Host ''

    Write-Host '-- PhValheim config --'
    $cfg = Join-Path $env:APPDATA 'PhValheim'
    if (Test-Path $cfg) { Write-Ok "Config dir present: $cfg" }
    else { Write-Ok 'Config dir not yet created (normal before first launch).' }
    Write-Host ''

    Write-Host '=== Diagnostics complete ==='
    Write-Host ''
}

# -- dispatch -----------------------------------------------------------------
switch ($Action) {
    'install'   { Invoke-Install }
    'uninstall' { Invoke-Uninstall }
    'diags'     { Invoke-Diags }
}
