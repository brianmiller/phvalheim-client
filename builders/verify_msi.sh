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
