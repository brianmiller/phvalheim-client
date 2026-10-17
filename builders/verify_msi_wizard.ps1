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

# Buttons in the dialog's CONTENT, never the window chrome.
#
# UI Automation exposes the titlebar's Minimize/Maximize/Close as ControlType.Button, right
# alongside the wizard's own Next/Install. The first run of this script clicked one: it matched
# "Close" on the progress dialog, which is the titlebar X, which raised "are you sure you want
# to cancel?" -- and then matched the X on THAT. The install limped to a confusing end state
# and the failure looked like a product fault. Chrome is not a control under test.
function Get-Buttons($window) {
  $btn = New-Object System.Windows.Automation.PropertyCondition(
           [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
           [System.Windows.Automation.ControlType]::Button)
  $found = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btn)

  # Collect the titlebar's own buttons so they can be excluded by identity rather than by
  # name -- a content button legitimately called "Close" must still be clickable.
  $chrome = @()
  $tbCond = New-Object System.Windows.Automation.PropertyCondition(
              [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
              [System.Windows.Automation.ControlType]::TitleBar)
  foreach ($tb in $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tbCond)) {
    foreach ($c in $tb.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btn)) {
      try { $chrome += $c.GetRuntimeId() -join '.' } catch { }
    }
  }

  $out = @()
  foreach ($b in $found) {
    try {
      if (-not $b.Current.IsEnabled -or $b.Current.IsOffscreen) { continue }
      $rid = $b.GetRuntimeId() -join '.'
      if ($chrome -contains $rid) { continue }
      $out += $b
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
# @(...) is load-bearing. On a zero-match the pipeline yields $null, and $null.Count is EMPTY,
# not 0 -- so `if ($inst.Count -eq 1)` and `if ($inst.Count -ge 1)` were both false and the
# failure message interpolated to " ARP entries after the wizard install". A count that cannot
# be read is worse than a wrong one: it makes every branch below take the else.
#
# HKCU is included as well as HKLM. This package is perMachine (ALLUSERS=1), so HKLM is where
# it should land -- but asserting only the expected location means a per-user registration
# reads as "not installed at all" rather than as the surprise it would be.
function Get-Installs {
  $keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  return @(Get-ItemProperty $keys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq 'PhValheim Client' } |
    Select-Object DisplayName, DisplayVersion, PSChildName, PSPath)
}

Write-Host ""
Write-Host "== 1. starting state =="
if (@(Get-Installs).Count -eq 0) { Ok "nothing installed to begin with" }
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

  $ctrl = @(Get-Installs)
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
$advance = @('^Next', '^Install$', '^Finish', '^&?Yes$', '^OK$', '^Close$', '^Repair')
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
  # nowhere else.
  #
  # But the TITLE is not the signal. msiexec's own "preparing to install" window is titled
  # "Windows Installer", and the first run of this script flagged it as an error dialog and
  # failed a perfectly good install. So read the dialog's TEXT and require it to actually say
  # something went wrong.
  foreach ($w in (Find-Windows '^Windows Installer$|Error')) {
    try {
      $txtCond = New-Object System.Windows.Automation.PropertyCondition(
                   [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                   [System.Windows.Automation.ControlType]::Text)
      $body = @()
      foreach ($t in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $txtCond)) {
        try { $body += $t.Current.Name } catch { }
      }
      $all = ($w.Current.Name + ' ' + ($body -join ' ')).Trim()
      if ($all -match 'error|failed|cannot|unexpected|not be installed|Internal Error|\b2\d{3}\b') {
        Write-Host "    !! installer ERROR dialog: $all"
        $clicks.Add("ERRORDIALOG: $all")
      }
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
  # 2826 is a LAYOUT note -- "control X extends beyond the boundaries of the dialog by N
  # pixels" -- logged at DEBUG level on installs that succeed. The first run of this script
  # treated it as fatal and failed a working install. It is still worth seeing, so it is
  # reported separately rather than silently dropped: a control overflowing its dialog is a
  # real (if cosmetic) defect in the .wxs.
  $all2xxx  = @(Select-String -Path $log -Pattern 'Error 2\d{3}' -AllMatches)
  $cosmetic = @($all2xxx | Where-Object { $_.Line -match 'DEBUG: Error 2826' })
  $real     = @($all2xxx | Where-Object { $_.Line -notmatch 'DEBUG: Error 2826' })

  if ($cosmetic.Count -gt 0) {
    $px = @($cosmetic | ForEach-Object {
      if ($_.Line -match 'Control (\S+) on dialog (\S+) extends beyond[^0-9]*(\d+) pixel') {
        "$($Matches[2])/$($Matches[1]) by $($Matches[3])px"
      }
    } | Where-Object { $_ } | Select-Object -Unique)
    Write-Host "  note: $($cosmetic.Count) cosmetic 2826 layout warning(s) -- dialog controls"
    Write-Host "        overflow their dialog. Not fatal, but it is a .wxs defect:"
    $px | ForEach-Object { Write-Host "          $_" }
  }

  if ($real.Count -eq 0) {
    Ok "the verbose log contains no installer error beyond the cosmetic 2826 layout notes"
  } else {
    Bad "the verbose log contains a real installer error" `
        (($real | Select-Object -First 5 | ForEach-Object { $_.Line.Trim() }) -join "`n        ")
  }
}

# @() at the CALL SITE, not just inside the function. A function that returns a
# single-element array has it UNROLLED to a scalar on output, so the @() inside Get-Installs
# does not survive the return -- which is why the count kept interpolating blank even after
# the function was fixed. Wrapping here is what actually binds an array.
$inst = @(Get-Installs)

# Dumped before it is judged. The previous run asserted "$($inst.Count) ARP entries" and
# printed nothing where the number should be, while the very next line read the version out
# of $inst[0] successfully -- two statements that cannot both be true, and no way to tell
# which was lying. A failure that cannot be read costs another whole CI round trip.
Write-Host "    ARP enumeration found $($inst.Count) entry/entries:"
foreach ($e in $inst) {
  Write-Host "      $($e.DisplayName) $($e.DisplayVersion)  [$($e.PSChildName)]"
  Write-Host "        in $($e.PSPath)"
}

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
if (@(Get-Installs).Count -eq 0) { Ok "no ARP entries remain" }
else { Bad "entries remain after uninstall" }

Write-Host ""
Write-Host "$script:Pass passed, $script:Fail failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
