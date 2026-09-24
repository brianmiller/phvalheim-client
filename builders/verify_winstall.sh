#!/usr/bin/env bash
#
# Static gate for winstall.ps1, the Windows install-script path.
#
# There is no Windows in this build environment, so this cannot tell you the
# install WORKS -- only that the script is well-formed and still agrees with the
# .msi about where things go. Real-hardware testing is the other half and this
# is not a substitute for it; see docs/WINDOWS-INSTALL-SCRIPT.md.
#
# What it does catch, and why each one is here:
#
#   1. The script parses.
#   2. The uninstaller the script GENERATES at install time parses. That body is
#      a here-string, so it is invisible to check 1 -- a quoting mistake there
#      produces a perfectly valid winstall.ps1 that writes a broken uninstaller,
#      and you find out when someone tries to remove the product.
#   3. PSScriptAnalyzer is clean at Error/Warning.
#   4. The script and builders/wxs/phvalheim-client.wxs still agree on the
#      install directory, the exe name and the URL-scheme command. These are a
#      contract with already-shipped installs: if the .wxs moves and this does
#      not, phvalheim:// links break for anyone who switches between them.
#
# Usage: bash builders/verify_winstall.sh
set -u

gitRoot=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$gitRoot/winstall.ps1"
wxs="$gitRoot/builders/wxs/phvalheim-client.wxs"
image="mcr.microsoft.com/powershell:latest"

pass=0; fail=0
ok()   { echo "  [OK]  $1"; pass=$((pass+1)); }
bad()  { echo "  [XX]  $1"; echo "        expected: $2"; echo "        actual:   $3"; fail=$((fail+1)); }

echo
echo "=== winstall.ps1 verification ==="
echo

for f in "$script" "$wxs"; do
	if [ ! -s "$f" ]; then
		echo "  [XX]  missing or empty: $f"
		exit 1
	fi
done

# ── 1-3. PowerShell-side checks, run in a container ──────────────────────────
echo "-- PowerShell --"
docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >/dev/null 2>&1

psout=$(docker run --rm -v "$gitRoot":/w:ro "$image" pwsh -NoProfile -Command '
$ErrorActionPreference = "Stop"
$errs = $null; $toks = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile("/w/winstall.ps1", [ref]$toks, [ref]$errs)
if ($errs) {
    Write-Output "FAIL`tscript parses`tno parse errors`t$($errs.Count) errors, first at line $($errs[0].Extent.StartLineNumber): $($errs[0].Message)"
    exit 0
}
Write-Output "PASS`tscript parses`t$($toks.Count) tokens"

# The generated uninstaller. Evaluate the here-string SOURCE once, exactly as
# the script will at runtime. Do NOT expand the AST node value instead: that
# text already has its escapes resolved, so expanding it a second time mangles
# every backtick and reports failures that are not real.
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Register-ArpEntry" }, $true)
if (-not $fn) {
    Write-Output "FAIL`tgenerated uninstaller`tRegister-ArpEntry exists`tfunction not found - was it renamed?"
} else {
    $hd = $fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true) |
          Where-Object { $_.Extent.Text -like "@`"*" } | Select-Object -First 1
    if (-not $hd) {
        Write-Output "FAIL`tgenerated uninstaller`ta here-string in Register-ArpEntry`tnone found"
    } else {
        $ProductName = "PhValheim Client"; $ExeName = "phvalheim-client.exe"
        $ClassesKey  = "Software\Classes\phvalheim"
        $ArpKey      = "Software\Microsoft\Windows\CurrentVersion\Uninstall\PhValheimClient"
        $InstallDir  = "C:\Users\t\AppData\Roaming\PhValheim\phvalheim-client"
        $body = Invoke-Expression $hd.Extent.Text
        $e2 = $null; $t2 = $null
        [System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$t2, [ref]$e2) | Out-Null
        if ($e2) {
            Write-Output "FAIL`tgenerated uninstaller parses`tno parse errors`tline $($e2[0].Extent.StartLineNumber): $($e2[0].Message)"
        } else {
            Write-Output "PASS`tgenerated uninstaller parses`t$($body.Split([char]10).Count) lines"
        }
        # A parser that accepts everything would pass the check above no matter
        # what. Prove it can fail.
        $e3 = $null
        [System.Management.Automation.Language.Parser]::ParseInput("if (", [ref]$t2, [ref]$e3) | Out-Null
        if ($e3) { Write-Output "PASS`tnegative control`tbroken input rejected ($($e3.Count) errors)" }
        else     { Write-Output "FAIL`tnegative control`tparser rejects broken input`tit accepted it - the check above proves nothing" }
    }
}

try {
    Install-Module PSScriptAnalyzer -RequiredVersion 1.22.0 -Force -Scope CurrentUser -ErrorAction Stop *>$null
    $r = Invoke-ScriptAnalyzer -Path /w/winstall.ps1 -Severity Error,Warning
    if (-not $r) { Write-Output "PASS`tPSScriptAnalyzer`t0 errors, 0 warnings" }
    else {
        $first = $r[0]
        Write-Output "FAIL`tPSScriptAnalyzer`tclean at Error/Warning`t$($r.Count) finding(s), first: line $($first.Line) $($first.RuleName)"
    }
} catch {
    Write-Output "WARN`tPSScriptAnalyzer`tcould not run: $($_.Exception.Message)"
}
' 2>/dev/null)

if [ -z "$psout" ]; then
	bad "PowerShell checks" "output from the container" "nothing - is docker working?"
else
	while IFS=$'\t' read -r verdict name expected actual; do
		case "$verdict" in
			PASS) ok "$name ($expected)" ;;
			WARN) echo "  [!!]  $name -- $expected" ;;
			FAIL) bad "$name" "$expected" "${actual:-see above}" ;;
		esac
	done <<< "$psout"
fi
echo

# ── 4. Drift against the .wxs ────────────────────────────────────────────────
# Both files hardcode the same three facts. They are a contract with installs
# that already exist on users' machines, so they cannot be allowed to diverge
# silently.
echo "-- Agreement with the .msi --"

# The install directory, as the .wxs spells it inside the registered command.
if grep -q 'PhValheim\\phvalheim-client\\phvalheim-client.exe' "$wxs"; then
	if grep -q "PhValheim\\\\phvalheim-client\\\\\$ExeName" "$script"; then
		ok "URL-scheme command path matches the .wxs"
	else
		bad "URL-scheme command path" \
		    'winstall.ps1 to register %appdata%\PhValheim\phvalheim-client\<exe>' \
		    "not found in winstall.ps1"
	fi
else
	bad "URL-scheme command path" \
	    'the .wxs to register %appdata%\PhValheim\phvalheim-client\phvalheim-client.exe' \
	    "the .wxs changed - winstall.ps1 needs the same change"
fi

# REG_EXPAND_SZ. As REG_SZ the handler silently does nothing, and every string
# comparison of the value still passes.
if grep -q 'Type="expandable"' "$wxs"; then
	if grep -q 'RegistryValueKind\]::ExpandString' "$script"; then
		ok "URL-scheme command is REG_EXPAND_SZ in both"
	else
		bad "URL-scheme value type" "ExpandString in winstall.ps1" "not found"
	fi
else
	bad "URL-scheme value type" 'Type="expandable" in the .wxs' "not found"
fi

# The "URL Protocol" marker is what makes Windows treat the key as a scheme.
if grep -q '"URL Protocol"' "$script"; then
	ok '"URL Protocol" marker written by winstall.ps1'
else
	bad '"URL Protocol" marker' "winstall.ps1 to write it" "not found"
fi

# The asset name the script downloads has to be the one the build produces.
assetPat=$(grep -o 'phvalheim-client-\$resolved-x86_64\.msi' "$script" | head -1)
if [ -n "$assetPat" ]; then
	ok "downloads phvalheim-client-<version>-x86_64.msi"
else
	bad "release asset name" "phvalheim-client-<version>-x86_64.msi" "pattern not found in winstall.ps1"
fi

echo
echo "-- MSI-to-script migration --"

# Ordering is the whole correctness argument for migration and it is invisible
# to any parser: both installs own the same directory, so the MSI's uninstall
# must run BEFORE the payload is placed, or it deletes what was just written --
# and every step still reports success. Assert the order by line number.
lnRemove=$(grep -n 'Remove-MsiInstall -Existing' "$script" | head -1 | cut -d: -f1)
lnInstall=$(grep -n 'Install-FromTree -SourceDir' "$script" | head -1 | cut -d: -f1)
lnExpand=$(grep -n 'Expand-MsiPayload -MsiPath' "$script" | head -1 | cut -d: -f1)

if [ -z "$lnRemove" ]; then
	bad "migration removes the MSI" "a Remove-MsiInstall call in the install path" "not found"
elif [ -z "$lnInstall" ] || [ -z "$lnExpand" ]; then
	bad "migration ordering" "Expand-MsiPayload and Install-FromTree calls" "not found"
else
	if [ "$lnRemove" -lt "$lnInstall" ]; then
		ok "MSI removal precedes Install-FromTree (line $lnRemove < $lnInstall)"
	else
		bad "MSI removal ordering" \
		    "Remove-MsiInstall before Install-FromTree" \
		    "removal at line $lnRemove, install at line $lnInstall -- the uninstall would delete the new payload"
	fi

	# The other half: the removal must come AFTER the payload exists, so a
	# failed download cannot leave the user with neither install.
	if [ "$lnRemove" -gt "$lnExpand" ]; then
		ok "MSI removal follows payload extraction (line $lnExpand < $lnRemove)"
	else
		bad "MSI removal ordering" \
		    "Remove-MsiInstall after Expand-MsiPayload" \
		    "removal at line $lnRemove, extract at line $lnExpand -- a failed download would leave nothing installed"
	fi
fi

# msiexec reporting success and msiexec having done nothing are indistinguishable
# from the exit code, and installing on top of a surviving MSI is the exact
# broken state migration exists to avoid.
if grep -q 'still = Get-MsiInstall' "$script"; then
	ok "removal is re-checked rather than trusted to the exit code"
else
	bad "removal verification" "a Get-MsiInstall re-check after msiexec /x" "not found"
fi

if grep -q "'/x'" "$script" && grep -q 'Verb RunAs' "$script"; then
	ok "uninstall runs msiexec /x elevated"
else
	bad "elevated uninstall" "msiexec /x via -Verb RunAs" "not found"
fi

echo
echo "=== $pass passed, $fail failed ==="
echo
[ "$fail" -eq 0 ] || exit 1
