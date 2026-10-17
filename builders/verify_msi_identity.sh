#!/bin/bash
# Check every PUBLISHED .msi against builders/msi-productcodes.tsv.
#
# WHY. The .wxs uses <Product Id="*">, so every build mints a new ProductCode. Two .msi files
# with the same ProductVersion are different products to Windows, and the same-version row in
# the Upgrade table refuses to install one over the other. So a rebuilt-and-re-uploaded asset
# strands everyone who downloaded the first one.
#
# On 2026-10-17 I did exactly that: the 2.0.15 msi was built at 01:24, attached, then rebuilt at
# 04:40 and clobbered the asset. Anyone who downloaded it in that window now holds a product the
# published installer will refuse to upgrade. Nothing noticed.
#
# This compares what is PUBLISHED against a committed ledger, so the next re-upload fails CI.
#
# Usage:  builders/verify_msi_identity.sh [version ...]      (default: every version in the ledger)

set -u
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LEDGER="$REPO/builders/msi-productcodes.tsv"

PASS=0; FAIL=0
ok(){   echo "  PASS: $1"; PASS=$((PASS+1)); }
bad(){  echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL+1)); }

command -v msiinfo >/dev/null 2>&1 || { echo "FATAL: msitools (msiinfo) not installed"; exit 1; }
[ -f "$LEDGER" ] || { echo "FATAL: $LEDGER missing"; exit 1; }

prop(){ msiinfo export "$1" Property 2>/dev/null | tr -d '\r' | awk -F'\t' -v k="$2" '$1==k{print $2}'; }

# --record <version> [--replace]
#
# Read the identity of the PUBLISHED asset and write it into the ledger. This is the step that
# arms the guard: until a version has a row, builders/msi_rebuild_guard.sh has nothing to refuse
# a rebuild against, and the next accidental rebuild strands people silently.
#
# It records what is PUBLISHED, never what is sitting in builds/ -- a local file may well be a
# later rebuild than the asset players are downloading, which is the exact confusion that caused
# the 2.0.15 incident.
if [ "${1:-}" = "--record" ]; then
	v="${2:-}"
	replace=0
	[ "${3:-}" = "--replace" ] && replace=1
	if [ -z "$v" ]; then echo "usage: $0 --record <version> [--replace]"; exit 1; fi

	TMPR=$(mktemp -d); trap 'rm -rf "$TMPR"' EXIT
	if ! gh release download "$v" -p '*x86_64.msi' -D "$TMPR" >/dev/null 2>&1; then
		echo "FAIL: could not download the published .msi for $v."
		echo "      Publish the asset to its release first -- this records what players GET,"
		echo "      not what is in builds/."
		exit 1
	fi
	f=$(find "$TMPR" -name '*.msi' | head -1)
	[ -n "$f" ] || { echo "FAIL: the $v release has no .msi asset"; exit 1; }

	pc=$(prop "$f" ProductCode)
	uc=$(prop "$f" UpgradeCode)
	pv=$(prop "$f" ProductVersion)
	if [ -z "$pc" ] || [ -z "$uc" ]; then
		echo "FAIL: could not read ProductCode/UpgradeCode out of the published $v asset"
		exit 1
	fi
	if [ "$pv" != "$v" ]; then
		echo "FAIL: the asset on the $v release reports ProductVersion '$pv'."
		echo "      Recording it would put a lie in the ledger. Fix the asset."
		exit 1
	fi

	existing=$(grep -E "^${v}	" "$LEDGER" | head -1)
	if [ -n "$existing" ]; then
		had=$(printf '%s' "$existing" | cut -f2)
		if [ "$had" = "$pc" ]; then
			echo "OK: $v is already recorded as $pc -- ledger already matches what is published."
			exit 0
		fi
		if [ "$replace" != "1" ]; then
			echo "REFUSING: the ledger says $v is $had but the published asset is $pc."
			echo
			echo "  The published asset was REPLACED by a rebuild. Anyone who downloaded the"
			echo "  earlier file cannot upgrade to this one or cleanly reinstall."
			echo "  Overwriting the ledger hides that rather than fixing it."
			echo
			echo "  Either restore the original asset, or ship a new version number."
			echo "  If you have decided to accept the breakage, re-run with --replace."
			exit 1
		fi
		# sed cannot be trusted with the braces; rewrite the line with awk instead.
		awk -F'\t' -v OFS='\t' -v v="$v" -v pc="$pc" -v uc="$uc" \
			'$1==v{$2=pc; $3=uc} {print}' "$LEDGER" > "$LEDGER.new" \
			&& mv "$LEDGER.new" "$LEDGER"
		echo "REPLACED: $v is now recorded as $pc (was $had)."
		exit 0
	fi

	printf '%s\t%s\t%s\n' "$v" "$pc" "$uc" >> "$LEDGER"
	echo "RECORDED: $v  $pc  $uc"
	echo "  Commit builders/msi-productcodes.tsv -- the guard and the CI check both read it."
	exit 0
fi

versions=("$@")
if [ "${#versions[@]}" -eq 0 ]; then
	mapfile -t versions < <(grep -vE '^\s*#|^\s*$' "$LEDGER" | cut -f1)
fi

# A ledger that matched nothing would pass silently -- the same vacuous-gate shape as an empty
# test glob. Refuse.
if [ "${#versions[@]}" -eq 0 ]; then
	echo "FAIL: no versions to check -- the ledger is empty or unparsable"
	exit 1
fi
echo "checking ${#versions[@]} version(s) against the ledger"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
expectedUpgrade=""

for v in "${versions[@]}"; do
	row=$(grep -E "^${v}	" "$LEDGER" | head -1)
	if [ -z "$row" ]; then bad "$v is not in the ledger"; continue; fi
	wantPC=$(printf '%s' "$row" | cut -f2)
	wantUC=$(printf '%s' "$row" | cut -f3)
	[ -z "$expectedUpgrade" ] && expectedUpgrade="$wantUC"

	if ! gh release download "$v" -p '*x86_64.msi' -D "$TMP/$v" >/dev/null 2>&1; then
		bad "$v: could not download the published .msi"
		continue
	fi
	f=$(find "$TMP/$v" -name '*.msi' | head -1)
	[ -n "$f" ] || { bad "$v: no .msi in the release assets"; continue; }

	gotPC=$(prop "$f" ProductCode)
	gotUC=$(prop "$f" UpgradeCode)
	gotVer=$(prop "$f" ProductVersion)

	[ "$gotVer" = "$v" ] \
		&& ok "$v: ProductVersion matches the release tag" \
		|| bad "$v: ProductVersion is '$gotVer', not '$v'" "the asset is mislabelled"

	if [ "$gotPC" = "$wantPC" ]; then
		ok "$v: ProductCode matches the ledger"
	else
		bad "$v: ProductCode CHANGED -- the published asset was rebuilt and re-uploaded" \
		    "ledger=$wantPC  published=$gotPC
        Anyone who downloaded the earlier file cannot upgrade to this one.
        Either restore the original asset, or ship a new version number."
	fi

	# UpgradeCode must be identical on every version, not merely equal to its own ledger row --
	# comparing each row to itself would pass even if the whole ledger drifted.
	if [ "$gotUC" = "$expectedUpgrade" ]; then
		ok "$v: UpgradeCode is the shared one ($gotUC)"
	else
		bad "$v: UpgradeCode differs from the other versions" \
		    "this=$gotUC  shared=$expectedUpgrade -- old installs would be left on disk"
	fi
done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
