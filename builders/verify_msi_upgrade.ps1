# Real install -> upgrade -> uninstall of the SHIPPED .msi files, on real Windows.
#
# WHY THIS EXISTS. A Discord user upgrading 2.0.14 -> 2.0.15 got "The installer encountered an
# unexpected error installing this package." Everything we had was static: verify_msi.sh reads
# the Upgrade table with msiinfo and checks the GUIDs field by field. That cannot catch a
# failure that only happens when msiexec actually runs the sequences -- and the upgrade path
# traverses a DIFFERENT dialog set than a fresh install, which is where the 2814 bug lived.
#
# TWO UI MODES, DELIBERATELY. /qn skips InstallUISequence ENTIRELY, so a silent-only test would
# have missed 2814 and would miss its next cousin. The upgrade leg runs /qr (reduced UI): it
# processes the UI sequence, shows a progress dialog, and needs no clicks -- which is what makes
# it runnable on a headless runner.
#
# Usage:
#   verify_msi_upgrade.ps1 -OldMsi a.msi -OldVersion 2.0.14 -NewMsi b.msi -NewVersion 2.0.15
#   verify_msi_upgrade.ps1 -NewMsi b.msi -NewVersion 2.0.15            # fresh install only

param(
  [string]$OldMsi = "",
  [string]$OldVersion = "",
  [Parameter(Mandatory=$true)][string]$NewMsi,
  [Parameter(Mandatory=$true)][string]$NewVersion,
  [string]$ExpectedExeSha256 = "",
  [string]$LogDir = "msi-logs"
)

$ErrorActionPreference = "Stop"
$script:Pass = 0
$script:Fail = 0
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Ok($m)  { Write-Host "  PASS: $m";                 $script:Pass++ }
function Bad($m, $d = "") {
  Write-Host "  FAIL: $m"
  if ($d) { Write-Host "        $d" }
  $script:Fail++
}

# Every PhValheim entry in Add/Remove Programs, from BOTH registry views.
# A 64-bit msiexec writes the native view; a 32-bit package writes Wow6432Node. Reading only
# one view is how "exactly one install" can be true and wrong at the same time.
function Get-Installs {
  $keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  # @(...) matters even though this currently passes: on a zero match the pipeline yields
  # $null, and $null.Count is EMPTY rather than 0, so every `$inst.Count -eq N` test below
  # would be false and the failure message would interpolate a blank count. Latent here, and
  # it bit verify_msi_wizard.ps1 for real on its first run.
  return @(Get-ItemProperty $keys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq 'PhValheim Client' } |
    Select-Object DisplayName, DisplayVersion, PSChildName)
}

# msiexec returns immediately unless waited on, and its exit code is the only verdict.
#   0    success
#   3010 success, reboot required
#   1603 fatal -- this is what a failed LaunchCondition gives under /qn
#   1638 another version of this product is already installed
function Invoke-Msi($argList, $logName) {
  $log = Join-Path $LogDir $logName
  $all = $argList + @("/l*v", "`"$log`"")
  $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $all -Wait -PassThru
  return @{ Code = $p.ExitCode; Log = $log }
}

function Show-LogTail($log, $lines = 25) {
  if (Test-Path $log) {
    Write-Host "        --- tail of $log ---"
    Get-Content $log -Tail $lines | ForEach-Object { Write-Host "        $_" }
  }
}

Write-Host ""
Write-Host "== starting state =="
$before = Get-Installs
if ($before.Count -eq 0) { Ok "no PhValheim Client installed to begin with" }
else { Bad "the runner already has $($before.Count) install(s)" ($before | Out-String) }

# ---------------------------------------------------------------------------
# Leg 1: install the OLD version, if one was given.
# ---------------------------------------------------------------------------
if ($OldMsi) {
  Write-Host ""
  Write-Host "== leg 1: install $OldVersion (/qn) =="
  $r = Invoke-Msi @("/i", "`"$OldMsi`"", "/qn") "install-$OldVersion.log"
  if ($r.Code -eq 0 -or $r.Code -eq 3010) { Ok "$OldVersion installed (exit $($r.Code))" }
  else { Bad "$OldVersion failed to install (exit $($r.Code))"; Show-LogTail $r.Log }

  $inst = Get-Installs
  if ($inst.Count -eq 1) { Ok "exactly one ARP entry after installing $OldVersion" }
  else { Bad "$($inst.Count) ARP entries after installing $OldVersion" ($inst | Out-String) }
  if ($inst.Count -ge 1 -and $inst[0].DisplayVersion -eq $OldVersion) {
    Ok "ARP reports $OldVersion"
  } else {
    Bad "ARP reports '$($inst[0].DisplayVersion)', expected $OldVersion"
  }
}

# ---------------------------------------------------------------------------
# Leg 2: install the NEW version over it. /qr so the UI sequence really runs.
# ---------------------------------------------------------------------------
Write-Host ""
$what = if ($OldMsi) { "upgrade $OldVersion -> $NewVersion" } else { "fresh install $NewVersion" }
Write-Host "== leg 2: $what (/qr -- UI sequence DOES run) =="
$r = Invoke-Msi @("/i", "`"$NewMsi`"", "/qr") "upgrade-to-$NewVersion.log"
if ($r.Code -eq 0 -or $r.Code -eq 3010) {
  Ok "$what succeeded (exit $($r.Code))"
} else {
  Bad "$what FAILED (exit $($r.Code))" "this is the reported class of failure"
  Show-LogTail $r.Log 40
}

# THE ASSERTION THAT CATCHES THE PARALLEL-INSTALL BUG. Two 2.0.13-era installs once sat side by
# side because the same-version case matched no Upgrade row. One entry, not two.
$inst = Get-Installs
if ($inst.Count -eq 1) { Ok "exactly ONE ARP entry after $what (no parallel install)" }
else { Bad "$($inst.Count) ARP entries after $what" ($inst | Out-String) }

if ($inst.Count -ge 1 -and $inst[0].DisplayVersion -eq $NewVersion) {
  Ok "ARP reports $NewVersion"
} else {
  Bad "ARP reports '$($inst[0].DisplayVersion)', expected $NewVersion"
}

# The payload must actually be on disk AND be the new build -- an upgrade that registers the
# new version but leaves the old binary is the failure mode a registry-only check cannot see.
#
# IT DOES NOT INSTALL TO PROGRAM FILES. The first cut of this searched
# "C:\Program Files","C:\Program Files (x86)" and failed on a working upgrade -- the package
# puts its payload under AppDataFolder\PhValheim\phvalheim-client (see the Directory table:
# INSTALLFOLDER -> PhValheimDir -> AppDataFolder). The product is perMachine, so depending on
# the account msiexec elevates to, that resolves either to the installing user's Roaming or to
# the SYSTEM profile's. Search every candidate rather than assuming one.
$roots = @(
  (Join-Path $env:APPDATA 'PhValheim'),
  'C:\Windows\System32\config\systemprofile\AppData\Roaming\PhValheim',
  'C:\Windows\SysWOW64\config\systemprofile\AppData\Roaming\PhValheim',
  'C:\Program Files',
  'C:\Program Files (x86)'
) | Where-Object { Test-Path $_ }

$exe = $null
foreach ($r in $roots) {
  $hit = Get-ChildItem -Path $r -Filter 'phvalheim-client.exe' -Recurse -ErrorAction SilentlyContinue |
         Select-Object -First 1
  if ($hit) { $exe = $hit; break }
}

if ($exe) {
  Ok "the installed binary exists ($($exe.FullName), $([math]::Round($exe.Length/1MB,1)) MB)"
  if ($ExpectedExeSha256) {
    $actualHash = (Get-FileHash $exe.FullName -Algorithm SHA256).Hash
    if ($actualHash -eq $ExpectedExeSha256) { Ok "installed payload matches the candidate SHA256" }
    else { Bad "installed payload SHA256 differs from the candidate" "$actualHash" }
  }


  # The stronger claim: it is THIS version, not the one we upgraded from. Without this the
  # check only proves some binary is present, which an upgrade that silently kept the old
  # payload would also satisfy.
  $fv = $exe.VersionInfo.FileVersion
  if ([string]::IsNullOrWhiteSpace($fv)) {
    Write-Host "  note: the binary carries no FileVersion metadata, so the version could not be"
    Write-Host "        confirmed from disk -- ARP agreeing on $NewVersion is all we have here."
  } elseif ($fv -like "$NewVersion*") {
    Ok "and it reports $fv on disk -- the payload really was replaced"
  } else {
    Bad "the binary on disk reports $fv, expected $NewVersion" `
        "ARP was updated but the payload was not -- a registry-only upgrade"
  }
} else {
  Bad "no phvalheim-client.exe found after $what" `
      ("searched: " + ($roots -join '; '))
}

# ---------------------------------------------------------------------------
# Leg 3: the same .msi again. This is maintenance mode, NOT an error -- and it must not
# duplicate the product either.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "== leg 3: re-running the SAME package must not duplicate or error =="
$r = Invoke-Msi @("/i", "`"$NewMsi`"", "/qn", "REINSTALL=ALL", "REINSTALLMODE=vomus") "reinstall-$NewVersion.log"
if ($r.Code -eq 0 -or $r.Code -eq 3010) { Ok "repair/reinstall of the same package succeeded (exit $($r.Code))" }
else { Bad "repair of the same package failed (exit $($r.Code))"; Show-LogTail $r.Log }
$inst = Get-Installs
if ($inst.Count -eq 1) { Ok "still exactly one ARP entry after the repair" }
else { Bad "$($inst.Count) ARP entries after the repair" ($inst | Out-String) }

# ---------------------------------------------------------------------------
# Leg 4: uninstall must leave nothing behind, or the next upgrade starts dirty.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "== leg 4: uninstall leaves nothing registered =="
$r = Invoke-Msi @("/x", "`"$NewMsi`"", "/qn") "uninstall-$NewVersion.log"
if ($r.Code -eq 0 -or $r.Code -eq 3010) { Ok "uninstall succeeded (exit $($r.Code))" }
else { Bad "uninstall failed (exit $($r.Code))"; Show-LogTail $r.Log }

$after = Get-Installs
if ($after.Count -eq 0) { Ok "no ARP entries remain" }
else { Bad "$($after.Count) ARP entries remain after uninstall" ($after | Out-String) }

Write-Host ""
Write-Host "$script:Pass passed, $script:Fail failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
