# Drive the FULL MSI wizard (/qf) by really clicking its buttons, via UI Automation.
#
# WHY THIS EXISTS, given verify_msi_upgrade.ps1 already runs installs. That script uses /qr:
# the UI sequence executes, but msiexec SUPPRESSES the modal dialogs. So WelcomeForm and
# ConfirmInstallForm never render and their control events never fire -- and that is exactly the
# path where an operator's live 2814 ("The installer encountered an unexpected error") happens.
# A pass under /qn or /qr says nothing about it. /qf is the only mode that renders them.
#
# HOW IT AVOIDS BEING A TEST THAT CANNOT SEE THE BUG:
#
#  1. A GUI capability probe runs FIRST, against a known-good window (notepad). If UI Automation
#     cannot see a window it is guaranteed to be able to see, this script FAILS rather than
#     reporting a green install -- a headless session would otherwise make every assertion below
#     pass for the wrong reason.
#
#  2. -NoClickControl runs the same /qf install and deliberately clicks NOTHING. It must time out
#     with the product NOT installed. If /qf completes on its own, then the clicking leg proves
#     nothing about clicking, and the dialogs it claims to exercise were never really gating.
#
#  3. Every dialog it clicks through is NAMED in the output, and the run fails if it never saw
#     a dialog at all.
#
# Usage:
#   verify_msi_wizard.ps1 -Msi path\to.msi -Version 2.0.16
#   verify_msi_wizard.ps1 -Msi path\to.msi -Version 2.0.16 -NoClickControl

param(
  [Parameter(Mandatory=$true)][string]$Msi,
  [Parameter(Mandatory=$true)][string]$Version,
  [switch]$NoClickControl,
  [int]$TimeoutSeconds = 240,
  [string]$LogDir = "msi-logs"
)

$ErrorActionPreference = "Stop"
$script:Pass = 0
$script:Fail = 0
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Ok($m)  { Write-Host "  PASS: $m"; $script:Pass++ }
function Bad($m, $d = "") {
  Write-Host "  FAIL: $m"
  if ($d) { Write-Host "        $d" }
  $script:Fail++
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms   # SendKeys, for buttons with no InvokePattern

# ---------------------------------------------------------------------------
# Window / button plumbing
# ---------------------------------------------------------------------------

# Top-level windows whose title matches, from the automation tree root.
function Find-Windows([string]$pattern) {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Window)
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
  $hits = @()
  foreach ($w in $all) {
    $n = ""
    try { $n = $w.Current.Name } catch { continue }
    if ($n -and $n -match $pattern) { $hits += $w }
  }
  return $hits
}

function Get-Buttons($window) {
  $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button)
  $found = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
  $out = @()
  foreach ($b in $found) {
    try {
      if ($b.Current.IsEnabled -and $b.Current.IsOffscreen -eq $false) { $out += $b }
    } catch { }
  }
  return $out
}

function Click-Button($button) {
  try {
    $p = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $p.Invoke()
    return $true
  } catch {
    # Some MSI dialog buttons expose no InvokePattern. Fall back to focus + space, which is a
    # real keyboard activation of the real control -- not a shortcut around the dialog.
    try {
      $button.SetFocus()
      Start-Sleep -Milliseconds 150
      [System.Windows.Forms.SendKeys]::SendWait(" ")
      return $true
    } catch { return $false }
  }
}

# ---------------------------------------------------------------------------
# 0. Can this session see a GUI at all?
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "== 0. GUI capability probe (control for the whole script) =="

$probeOk = $false
$probe = $null
try {
  $probe = Start-Process -FilePath "notepad.exe" -PassThru
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    if ((Find-Windows 'Notepad|Untitled').Count -gt 0) { $probeOk = $true; break }
    Start-Sleep -Milliseconds 500
  }
} catch { }
finally {
  if ($probe -and -not $probe.HasExited) { try { $probe.Kill() } catch { } }
}

if ($probeOk) {
  Ok "UI Automation can see a top-level window on this runner"
} else {
  Bad "UI Automation could NOT see a notepad window" @"
This session has no usable window station, so nothing below can observe the MSI wizard.
Reporting that as a failure on purpose: a green 'wizard install succeeded' from a blind
script is worse than no test. If GitHub's windows runners cannot host an interactive
desktop, this job needs a self-hosted Windows box -- it cannot be faked with /qr.
"@
  Write-Host ""
  Write-Host "$script:Pass passed, $script:Fail failed"
  exit 1
}

# ---------------------------------------------------------------------------
# Starting state
# ---------------------------------------------------------------------------
function Get-Installs {
  $keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  Get-ItemProperty $keys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq 'PhValheim Client' } |
    Select-Object DisplayName, DisplayVersion, PSChildName
}

Write-Host ""
Write-Host "== 1. starting state =="
if ((Get-Installs).Count -eq 0) { Ok "nothing installed to begin with" }
else { Bad "the runner already has PhValheim Client installed" }

# ---------------------------------------------------------------------------
# 2. The control leg: /qf with NOBODY clicking must NOT install.
# ---------------------------------------------------------------------------
if ($NoClickControl) {
  Write-Host ""
  Write-Host "== 2. CONTROL: /qf with no clicks must stall, not install =="

  $log = Join-Path $LogDir "wizard-control-$Version.log"
  $p = Start-Process -FilePath "msiexec.exe" `
        -ArgumentList @("/i", "`"$Msi`"", "/qf", "/l*v", "`"$log`"") -PassThru

  $waited = 0
  $sawDialog = $false
  while ($waited -lt 60 -and -not $p.HasExited) {
    if ((Find-Windows 'PhValheim').Count -gt 0) { $sawDialog = $true }
    Start-Sleep -Seconds 2; $waited += 2
  }

  if ($sawDialog) { Ok "the wizard rendered a dialog (so /qf really does show UI here)" }
  else { Bad "no PhValheim dialog appeared in ${waited}s under /qf" "the control cannot distinguish anything" }

  if (-not $p.HasExited) {
    Ok "msiexec is still waiting after ${waited}s -- the wizard does NOT self-advance"
  } else {
    Bad "msiexec exited on its own (code $($p.ExitCode)) with nobody clicking" @"
Then the clicking leg proves nothing: the install completes without the dialogs being
operated, so WelcomeForm/ConfirmInstallForm are not gating anything we are testing.
"@
  }

  $ctrl = Get-Installs
  if ($ctrl.Count -eq 0) { Ok "and nothing was installed" }
  else { Bad "$($ctrl.Count) install(s) appeared without a single click" }

  # Tear the stalled wizard down so the next leg starts clean.
  foreach ($w in (Find-Windows 'PhValheim')) {
    foreach ($b in (Get-Buttons $w)) {
      if ($b.Current.Name -match 'Cancel') { Click-Button $b | Out-Null }
    }
  }
  Start-Sleep -Seconds 3
  if (-not $p.HasExited) { try { $p.Kill() } catch { } }
  Start-Sleep -Seconds 2
  foreach ($leftover in (Get-Process msiexec -ErrorAction SilentlyContinue)) {
    if ($leftover.MainWindowHandle -ne 0) { try { $leftover.Kill() } catch { } }
  }

  Write-Host ""
  Write-Host "$script:Pass passed, $script:Fail failed"
  if ($script:Fail -gt 0) { exit 1 }
  exit 0
}

# ---------------------------------------------------------------------------
# 3. The real leg: click the wizard through to completion.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "== 2. /qf install, clicked through for real =="

$log = Join-Path $LogDir "wizard-install-$Version.log"
$proc = Start-Process -FilePath "msiexec.exe" `
          -ArgumentList @("/i", "`"$Msi`"", "/qf", "/l*v", "`"$log`"") -PassThru

$dialogsSeen = New-Object System.Collections.Generic.List[string]
$clicks      = New-Object System.Collections.Generic.List[string]
# Ordered by preference. Cancel and Back are deliberately absent: clicking either would walk
# the wizard backwards and the run could "succeed" by never installing anything.
$advance = @('^Next', '^Install$', '^Finish', '^Close', '^&?Yes$', '^OK$', '^Repair')
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastClick = Get-Date

while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
  $wins = Find-Windows 'PhValheim'
  foreach ($w in $wins) {
    $title = ""
    try { $title = $w.Current.Name } catch { }
    if ($title -and -not $dialogsSeen.Contains($title)) {
      $dialogsSeen.Add($title)
      Write-Host "    dialog: $title"
    }

    $buttons = Get-Buttons $w
    $names = @()
    foreach ($b in $buttons) { try { $names += $b.Current.Name } catch { } }
    if ($names.Count -gt 0) { Write-Host "      buttons: $($names -join ' | ')" }

    $clicked = $false
    foreach ($pat in $advance) {
      foreach ($b in $buttons) {
        $n = ""
        try { $n = $b.Current.Name } catch { continue }
        if ($n -match $pat) {
          if (Click-Button $b) {
            Write-Host "      clicked: $n"
            $clicks.Add("$title / $n")
            $lastClick = Get-Date
            $clicked = $true
          }
          break
        }
      }
      if ($clicked) { break }
    }
  }

  # An error dialog is the whole point of running /qf -- 2814 and friends surface here and
  # nowhere else. Capture its text before anything dismisses it.
  foreach ($w in (Find-Windows 'Installer|Error|Windows Installer')) {
    try {
      $txt = $w.Current.Name
      Write-Host "    !! installer dialog: $txt"
      $clicks.Add("ERRORDIALOG: $txt")
    } catch { }
  }

  Start-Sleep -Milliseconds 800
}

if ($dialogsSeen.Count -gt 0) {
  Ok "the wizard rendered $($dialogsSeen.Count) dialog(s): $($dialogsSeen -join '; ')"
} else {
  Bad "no wizard dialog was ever seen" "nothing was exercised -- do not read the result below as a pass"
}

if ($clicks.Count -gt 0) {
  Ok "clicked $($clicks.Count) control(s): $($clicks -join ', ')"
} else {
  Bad "no button was ever clicked" "the control events this test exists for did not fire"
}

$errDialogs = @($clicks | Where-Object { $_ -like 'ERRORDIALOG:*' })
if ($errDialogs.Count -eq 0) {
  Ok "no installer error dialog appeared"
} else {
  Bad "the installer raised an error dialog" ($errDialogs -join "`n        ")
}

if (-not $proc.HasExited) {
  Bad "msiexec never finished within ${TimeoutSeconds}s" `
      "last click was at $lastClick; the wizard is probably sitting on a dialog with no advance button"
  try { $proc.Kill() } catch { }
} else {
  if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
    Ok "msiexec exited $($proc.ExitCode)"
  } else {
    Bad "msiexec exited $($proc.ExitCode)" "1603 = fatal during install; 2814-class faults land here"
  }
}

# 2814 and every other 2xxx internal error is written to the verbose log whether or not a
# dialog survived long enough to be read.
if (Test-Path $log) {
  $internal = Select-String -Path $log -Pattern 'Internal Error 2\d{3}|error 28\d\d' -AllMatches
  if (-not $internal) {
    Ok "the verbose log contains no Internal Error 2xxx"
  } else {
    Bad "the verbose log contains an internal installer error" `
        (($internal | Select-Object -First 5 | ForEach-Object { $_.Line.Trim() }) -join "`n        ")
  }
}

$inst = Get-Installs
if ($inst.Count -eq 1) { Ok "exactly one ARP entry after the wizard install" }
else { Bad "$($inst.Count) ARP entries after the wizard install" }
if ($inst.Count -ge 1 -and $inst[0].DisplayVersion -eq $Version) { Ok "ARP reports $Version" }
else { Bad "ARP reports '$($inst[0].DisplayVersion)', expected $Version" }

# Same search set as verify_msi_upgrade.ps1: this package installs under AppDataFolder, not
# Program Files, and perMachine resolves that to either Roaming or the SYSTEM profile.
$roots = @(
  (Join-Path $env:APPDATA 'PhValheim'),
  'C:\Windows\System32\config\systemprofile\AppData\Roaming\PhValheim',
  'C:\Windows\SysWOW64\config\systemprofile\AppData\Roaming\PhValheim'
) | Where-Object { Test-Path $_ }

$exe = $null
foreach ($r in $roots) {
  $hit = Get-ChildItem -Path $r -Filter 'phvalheim-client.exe' -Recurse -ErrorAction SilentlyContinue |
         Select-Object -First 1
  if ($hit) { $exe = $hit; break }
}
if ($exe) { Ok "the payload is on disk ($($exe.FullName))" }
else { Bad "no phvalheim-client.exe after the wizard install" ("searched: " + ($roots -join '; ')) }

# ---------------------------------------------------------------------------
# 4. Clean up, so a matrix leg does not poison the next one.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "== 3. uninstall =="
$u = Start-Process -FilePath "msiexec.exe" `
       -ArgumentList @("/x", "`"$Msi`"", "/qn", "/l*v", "`"$(Join-Path $LogDir "wizard-uninstall-$Version.log")`"") `
       -Wait -PassThru
if ($u.ExitCode -eq 0 -or $u.ExitCode -eq 3010) { Ok "uninstall succeeded" }
else { Bad "uninstall failed (exit $($u.ExitCode))" }
if ((Get-Installs).Count -eq 0) { Ok "no ARP entries remain" }
else { Bad "entries remain after uninstall" }

Write-Host ""
Write-Host "$script:Pass passed, $script:Fail failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
