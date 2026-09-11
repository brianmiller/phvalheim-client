#!/bin/bash
#
# Verify a built .msi against the contract the .vdproj used to ship.
#
# WHY THIS EXISTS: building an MSI on Linux runs NO ICE validation -- light.exe's
# validator is Windows-only and wixl has no equivalent. Without these checks a
# structurally broken or silently-wrong MSI would ship looking fine.
#
# Two independent gates:
#   1. table assertions (msiinfo) -- checks the shipped contract field by field
#   2. wine smoke install         -- catches breakage the tables cannot show
#
# Run inside the builders/dockers/windows image.
#
# Usage: verify_msi.sh <path-to-msi> <expected-version> [--skip-wine]

set -u

msi="${1:?usage: verify_msi.sh <msi> <version> [--skip-wine]}"
expectVersion="${2:?usage: verify_msi.sh <msi> <version> [--skip-wine]}"
skipWine="${3:-}"

# Inherited verbatim from the .vdproj. If this ever changes, upgrades break.
expectUpgradeCode='{9799CDE9-1240-47AC-9891-AAB1F6FDB5E7}'
expectCommand='"%appdata%\PhValheim\phvalheim-client\phvalheim-client.exe" "%1"'

fails=0
checks=0

ok()   { checks=$((checks+1)); echo "  PASS  $1"; }
fail() { checks=$((checks+1)); fails=$((fails+1)); echo "  FAIL  $1"; echo "        expected: $2"; echo "        actual:   $3"; }

expect() { # expect <description> <expected> <actual>
	if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "$2" "$3"; fi
}

expectContains() { # expectContains <description> <needle> <haystack>
	case "$3" in
		*"$2"*) ok "$1" ;;
		*)      fail "$1" "contains: $2" "$3" ;;
	esac
}

# msiinfo export emits CRLF line endings (MSI tables are a Windows format).
# Left in place, every single string comparison below fails on a trailing \r
# while printing expected and actual as visually identical -- so strip it here,
# once, rather than at each call site.
msiexport() {
	msiinfo export "$msi" "$1" 2>/dev/null | tr -d '\r'
}

prop() { # read a row out of the Property table
	msiexport Property | awk -F'\t' -v k="$1" '$1==k {print $2; exit}'
}

echo
echo "Verifying $(basename "$msi")"
echo "================================================================"

if [ ! -s "$msi" ]; then
	echo "  FAIL  file is missing or empty: $msi"
	exit 1
fi

if ! msiinfo tables "$msi" >/dev/null 2>&1; then
	echo "  FAIL  not a readable MSI database: $msi"
	exit 1
fi

echo
echo "-- summary information --"
suminfo=$(msiinfo suminfo "$msi" 2>/dev/null | tr -d '\r')
# x64;1033 -- wixl only stamps this from the `-a x64` CLI flag. A Platform=
# attribute in the .wxs is warned-and-ignored, so this assertion is the only
# thing standing between us and shipping an x86-stamped package.
template=$(echo "$suminfo" | sed -n 's/^Template: *//p')
expect "arch/language template is x64;1033" "x64;1033" "$template"
expect "Subject is the product name" "PhValheim Client" "$(echo "$suminfo" | sed -n 's/^Subject: *//p')"
expect "Author is the manufacturer"   "Phospher"        "$(echo "$suminfo" | sed -n 's/^Author: *//p')"

echo
echo "-- product identity --"
expect "UpgradeCode is unchanged from 2.0.12" "$expectUpgradeCode" "$(prop UpgradeCode)"
expect "ProductVersion matches the csproj"    "$expectVersion"     "$(prop ProductVersion)"
expect "ProductName"                          "PhValheim Client"   "$(prop ProductName)"
expect "Manufacturer"                         "Phospher"           "$(prop Manufacturer)"
expect "ALLUSERS=1 (perMachine, as .vdproj)"  "1"                  "$(prop ALLUSERS)"
expect "ARPCONTACT"                           "posixone"           "$(prop ARPCONTACT)"
expect "ARPPRODUCTICON is set"                "phvalheim.ico"      "$(prop ARPPRODUCTICON)"

# ProductCode must be a fresh GUID per build (Product Id="*"), and must NOT
# collide with the UpgradeCode.
productCode=$(prop ProductCode)
case "$productCode" in
	\{????????-????-????-????-????????????\}) ok "ProductCode is a well-formed GUID ($productCode)" ;;
	*) fail "ProductCode is a well-formed GUID" "{GUID}" "$productCode" ;;
esac
if [ "$productCode" = "$expectUpgradeCode" ]; then
	fail "ProductCode differs from UpgradeCode" "different GUIDs" "both $productCode"
else
	ok "ProductCode differs from UpgradeCode"
fi

echo
echo "-- upgrade behaviour --"
upgrade=$(msiexport Upgrade)
expectContains "Upgrade table references our UpgradeCode" "$expectUpgradeCode" "$upgrade"
expectContains "major-upgrade detection present"   "WIX_UPGRADE_DETECTED"   "$upgrade"
expectContains "downgrade protection present"      "WIX_DOWNGRADE_DETECTED" "$upgrade"

echo
echo "-- payload --"
fileTable=$(msiexport File)
expectContains "phvalheim-client.exe is in the File table" "phvalheim-client.exe" "$fileTable"
expectContains "phvalheim-client.ico is in the File table" "phvalheim-client.ico" "$fileTable"

exeSize=$(echo "$fileTable" | awk -F'\t' '$3=="phvalheim-client.exe" {print $4; exit}')
if [ -n "$exeSize" ] && [ "$exeSize" -gt 10000000 ] 2>/dev/null; then
	ok "phvalheim-client.exe is a plausible size ($exeSize bytes)"
else
	fail "phvalheim-client.exe is a plausible size" ">10000000 bytes" "${exeSize:-<absent>}"
fi

# The cab has to actually be embedded, or the MSI is useless on its own.
expectContains "product.cab is embedded" "product.cab" "$(msiexport Media)"

echo
echo "-- phvalheim:// URL scheme --"
registry=$(msiexport Registry)
# Root 0 == HKCR.
cmdRow=$(echo "$registry" | awk -F'\t' '$3 ~ /shell\\open\\command/ {print; exit}')
rawCmdValue=$(echo "$cmdRow" | cut -f5)
expectContains "shell\\open\\command row exists" 'shell\open\command' "$registry"
expect         "command row is under HKCR (root 0)" "0" "$(echo "$cmdRow" | cut -f2)"

# REG_EXPAND_SZ is encoded in the Registry table by prefixing the value with
# '#%'. Strip that marker before comparing the command line itself, then assert
# the marker separately -- as plain REG_SZ, Windows would hand the literal
# string "%appdata%\..." to CreateProcess and the URL handler would silently
# never launch. Nothing else in this script can see that difference.
expect "command line points at the installed exe" "$expectCommand" "${rawCmdValue#\#%}"
if [ "$rawCmdValue" != "${rawCmdValue#\#%}" ]; then
	ok "command value is REG_EXPAND_SZ (#% marker present)"
else
	fail "command value is REG_EXPAND_SZ" "value prefixed '#%'" "$rawCmdValue"
fi

expectContains "'URL Protocol' marker value exists" "URL Protocol" "$registry"
expectContains "default value names the product" "PhValheim Client" "$registry"

echo
echo "-- component wiring --"
# A component can sit in the Registry/File tables and still never be installed,
# if nothing links it to a Feature. Dropping <ComponentRef Id="UrlScheme"/> does
# exactly that: every table assertion above still passes, and the shipped MSI
# quietly installs no URL handler. So assert the FeatureComponents linkage too.
featureComponents=$(msiexport FeatureComponents)
for component in ClientExe ClientIco UrlScheme; do
	if echo "$featureComponents" | awk -F'\t' -v c="$component" '$2==c {found=1} END {exit !found}'; then
		ok "$component is linked to a feature"
	else
		fail "$component is linked to a feature" "row in FeatureComponents" "absent -- component would never install"
	fi
done

echo
echo "-- installer UI --"
# 2.0.13's first build shipped with NO Dialog/Control tables at all. Every
# assertion above still passed, because the package was structurally valid --
# it just could not draw a single window. The user-visible result: a
# SUCCESSFUL install showed "Gathering required information" and then vanished
# with no completion page, indistinguishable from a crash, and a FAILED
# install was equally silent because FatalError/ErrorDlg were gone too.
# Neither the table assertions nor the wine smoke install below can see this:
# wine passes with /qn (which skips InstallUISequence entirely) and passes in
# full UI mode too. Hence an explicit floor.
dialogs=$(msiexport Dialog | tail -n +4 | cut -f1 | grep -c . || true)
controls=$(msiexport Control | tail -n +4 | grep -c . || true)
if [ "${dialogs:-0}" -ge 8 ]; then
	ok "installer has a dialog set ($dialogs dialogs, $controls controls)"
else
	fail "installer has a dialog set" ">=8 dialogs" "${dialogs:-0} -- a silent install is indistinguishable from a crash"
fi

# The .vdproj's own form names, re-authored in builders/wxs/ui-phvalheim.wxs.
# If these turn into WiX's stock names (WelcomeDlg, VerifyReadyDlg, ExitDialog,
# ...) then someone swapped in the stock dialog set, which is side-bitmap style
# over a solid maroon image and carries WiX boilerplate instead of the
# product's own text. FinishedForm is the completion page; FatalErrorForm and
# ErrorForm are the only way the package can report its own failure.
dialogList=$(msiexport Dialog | tail -n +4 | cut -f1)
ourDialogs="WelcomeForm ConfirmInstallForm ProgressForm FinishedForm MaintenanceForm FatalErrorForm UserExitForm CancelForm ErrorForm"
for dlg in $ourDialogs; do
	if echo "$dialogList" | grep -qx "$dlg"; then
		ok "dialog $dlg present"
	else
		fail "dialog $dlg present" "row in Dialog table" "absent"
	fi
done

# A SpawnDialog naming a dialog that was never pulled in is MSI error 2803 at
# runtime. VerifyReadyDlg spawns OutOfDiskDlg/OutOfRbDiskDlg on a low-disk
# install, and nothing else references them -- stock WixUI_Minimal ships this
# hole. Only reachable when the disk is full, so no smoke test will find it.
dangling=$(comm -23 \
	<(msiexport ControlEvent | tail -n +4 | awk -F'\t' '$3=="SpawnDialog" {print $4}' | sort -u) \
	<(echo "$dialogList" | sort -u) | tr '\n' ' ')
if [ -z "${dangling// /}" ]; then
	ok "every SpawnDialog target exists in the Dialog table"
else
	fail "every SpawnDialog target exists in the Dialog table" "no dangling targets" "$dangling(MSI error 2803 at runtime)"
fi

# The wizard's actual CONTENT. A dialog set can be present and correctly wired
# and still say nothing -- the stock WiX dialogs pass every check above while
# carrying generic boilerplate. These strings are the .vdproj's own, and their
# presence is the only thing distinguishing "the wizard" from "a wizard".
controlText=$(msiexport Control | tail -n +4)
while IFS='|' read -r label needle; do
	if echo "$controlText" | grep -qF "$needle"; then
		ok "wizard text: $label"
	else
		fail "wizard text: $label" "contains: $needle" "absent -- stock boilerplate?"
	fi
done <<'STRINGS'
welcome names the product and version|This is PhValheim [ProductVersion]'s Windows client.
welcome explains the phvalheim:// registration|A custom phvalheim:// URL will be registered to Windows
welcome explains world-file sync|kept in sync with the remote PhValheim server
welcome names the install location|kept in %appdata%\PhValheim
the .vdproj copyright notice|Zero Cool's garbage file
completion page confirms success|has been successfully installed.
confirm page|The installer is ready to install
confirm page tells the user what Next does|Click "Next" to start the installation.
progress page|is being installed.
fatal-error page tells the user what happened|The installer was interrupted before
maintenance page offers repair/remove|Select whether you want to repair or remove
STRINGS

# Every paragraph after the first lives past an embedded newline. Two separate
# mistakes silently drop them and leave a plausible-looking one-liner: reading
# the source MSI with `msiinfo export | awk` (which stops at the newline), and
# authoring the value as a Text="..." ATTRIBUTE (XML collapses newlines to
# spaces). Assert the multi-paragraph controls are actually multi-paragraph.
for ctl in WelcomeText BodyText1; do
	para=$(msiexport Control | awk -F'\t' -v c="$ctl" '$2==c {found=1} found && /^$/ {n++} $2!=c && /^[A-Za-z]+Form\t/ && found && $2!=c {exit} END {print n+0}')
	if [ "${para:-0}" -ge 1 ]; then
		ok "$ctl keeps its paragraph breaks ($((para+1)) paragraphs)"
	else
		fail "$ctl keeps its paragraph breaks" "2+ paragraphs" "1 -- newlines collapsed, text lost"
	fi
done

# Every visible string must carry an inline {\Style} prefix, as the .vdproj
# does. Setting the DefaultUIFont property is NOT enough -- Windows Installer
# ignores it, and an unstyled string renders BLUE and stops rendering at its
# first embedded newline. 2.0.13 shipped one blue paragraph where 2.0.12 shows
# four black ones, with byte-identical Control values and newlines; the only
# difference was this prefix. Invisible to every other check here.
# Scoped to the dialogs we author. `--ext ui` also drags in a stock CancelDlg
# that nothing references (our cancel path spawns CancelForm); it is unstyled
# dead weight, not a rendering bug. If a stock dialog ever became reachable the
# SpawnDialog and named-dialog checks above would catch it.
unstyled=$(msiexport Control | tail -n +4 | awk -F'\t' -v ours="$ourDialogs" '
	BEGIN { n = split(ours, a, " "); for (i = 1; i <= n; i++) mine[a[i]] = 1 }
	($3 == "Text" || $3 == "PushButton") && ($1 in mine) {
		if ($10 != "" && $10 !~ /^\{\\/) print $1 "/" $2
	}' | tr '\n' ' ')
if [ -z "${unstyled// /}" ]; then
	ok "every Text/PushButton string carries an inline style prefix"
else
	fail "every Text/PushButton string carries an inline style prefix" \
		"all prefixed {\\Style}" "$unstyled(renders blue, truncates at first newline)"
fi

# TextStyle.Color NULL renders every styled string BLUE on Windows. 2.0.12
# writes 0. No table assertion catches this; it is only visible on screen.
# The .vdproj's face is MS Sans Serif -- Tahoma renders visibly heavier.
textStyle=$(msiexport TextStyle | tail -n +4)
if [ -z "$textStyle" ]; then
	fail "TextStyle rows exist" "2 styles" "none"
else
	while IFS=$'\t' read -r id face size color bits; do
		[ -z "$id" ] && continue
		if [ "$color" = "0" ]; then
			ok "TextStyle $id has an explicit colour (black)"
		else
			fail "TextStyle $id has an explicit colour" "Color=0" "Color='${color}' -- NULL renders BLUE on Windows"
		fi
		expect "TextStyle $id uses the .vdproj face" "MS Sans Serif" "$face"
	done <<< "$textStyle"
fi

# The banner bitmap is the wizard's visual identity: a white 500x70 banner
# lifted from the .vdproj. Its absence means the stock maroon side-bitmap
# dialogs are back.
if msiexport Binary | tail -n +4 | cut -f1 | grep -qx PhvBanner; then
	ok "the .vdproj banner bitmap is embedded"
else
	fail "the .vdproj banner bitmap is embedded" "Binary row PhvBanner" "absent"
fi

# This product has never had a licence agreement page, and the repo has no
# LICENSE file. Stock WixUI_Minimal would add one via WelcomeEulaDlg; if it
# ever reappears, someone swapped the dialog set and invented licence text.
if echo "$dialogList" | grep -qi eula; then
	fail "no licence agreement page" "no Eula dialog" "$(echo "$dialogList" | grep -i eula | tr '\n' ' ')"
else
	ok "no licence agreement page (product has never had one)"
fi

echo
echo "-- signature --"
# osslsigncode's EXIT CODE reflects chain TRUST, not signature PRESENCE: a
# perfectly good self-signed signature exits 1 with "certificate verify error:
# self-signed certificate". Keying off the exit code would report every signed
# build as unsigned. Parse the output instead.
osslsigncode verify "$msi" >/tmp/sigverify.txt 2>&1
if grep -q "Current DigitalSignature" /tmp/sigverify.txt; then
	signer=$(sed -n 's/^[[:space:]]*Subject: *//p' /tmp/sigverify.txt | head -1)
	ok "MSI carries an Authenticode signature (${signer:-unknown subject})"

	# The real integrity question: does the stored digest match the recomputed
	# one? If signing ran before a later write to the file, these diverge.
	cur=$(sed -n 's/^Current DigitalSignature *: *//p'    /tmp/sigverify.txt | tr -d ' ')
	calc=$(sed -n 's/^Calculated DigitalSignature *: *//p' /tmp/sigverify.txt | tr -d ' ')
	if [ -n "$cur" ] && [ "$cur" = "$calc" ]; then
		ok "signature digest matches the file contents"
	else
		fail "signature digest matches the file contents" "$cur" "$calc"
	fi

	if grep -q "self-signed certificate" /tmp/sigverify.txt; then
		echo "  NOTE  certificate is self-signed, so Windows will still show"
		echo "        'Unknown Publisher'. Expected until a trusted cert is bought."
	fi
else
	echo "  NOTE  MSI is unsigned (set CODESIGN_PFX to sign)"
fi

if [ "$skipWine" != "--skip-wine" ] && command -v wine >/dev/null 2>&1; then
	echo
	echo "-- wine smoke install --"
	# wine implements MSI for real, so it rejects a structurally broken package.
	# This catches the class of failure the table assertions above cannot see.
	export WINEPREFIX="${WINEPREFIX:-/tmp/wineprefix}"
	export WINEDEBUG=-all
	rm -rf "$WINEPREFIX"
	if wineboot -i >/dev/null 2>&1; then
		wine msiexec /i "$(winepath -w "$msi" 2>/dev/null || echo "Z:$msi")" /qn >/tmp/wine-install.log 2>&1
		wineserver -w 2>/dev/null

		installed=$(find "$WINEPREFIX/drive_c/users" -path '*PhValheim/phvalheim-client/phvalheim-client.exe' 2>/dev/null | head -1)
		if [ -n "$installed" ]; then
			ok "exe installed to %AppData%\\PhValheim\\phvalheim-client\\"
			sz=$(stat -c%s "$installed" 2>/dev/null)
			expect "installed exe is byte-identical in size to the File table" "$exeSize" "$sz"
		else
			fail "exe installed to %AppData%\\PhValheim\\phvalheim-client\\" "file present" "not found (see /tmp/wine-install.log)"
		fi

		# Read the URL handler back out of wine's registry.
		sysreg="$WINEPREFIX/system.reg"
		userreg="$WINEPREFIX/user.reg"
		if grep -qi 'phvalheim\\\\shell\\\\open\\\\command' "$sysreg" "$userreg" 2>/dev/null; then
			ok "phvalheim:// handler registered in wine's registry"
		else
			fail "phvalheim:// handler registered in wine's registry" "key present" "not found"
		fi
		if grep -qi 'URL Protocol' "$sysreg" "$userreg" 2>/dev/null; then
			ok "'URL Protocol' marker written"
		else
			fail "'URL Protocol' marker written" "value present" "not found"
		fi
	else
		echo "  SKIP  wine prefix would not initialise; smoke install not run"
	fi
fi

echo
echo "================================================================"
if [ "$fails" -eq 0 ]; then
	echo "OK: $checks checks passed"
	exit 0
fi
echo "FAILED: $fails of $checks checks failed"
exit 1
