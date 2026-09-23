#!/bin/bash
#
# Verify an INSTALLED PhValheim Client on real macOS hardware.
#
# WHY THIS EXISTS: the macOS artifacts can be assembled on Linux (see
# docs/MACOS-BUILD-ON-LINUX.md), but nothing on Linux can answer the only
# question that actually matters -- does Apple Silicon agree to run the binary?
# An unsigned or wrongly-signed arm64 Mach-O is killed by AMFI at exec time and
# looks completely healthy to every static check.
#
# The pre-existing macinstall.sh diags never execute the binary: they read the
# version out of Info.plist with `defaults read`. So they pass on a binary macOS
# refuses to launch. That gap is what check 6 below closes.
#
# Run AFTER installing (macinstall.sh install). Needs no sudo.
#
# Usage: verify_macos.sh <expected-version> [results-tsv]
#
# When results-tsv is given, each check also appends
#   <status>\t<description>\t<detail>
# so CI can render a table without re-parsing console output.

set -u

expectVersion="${1:?usage: verify_macos.sh <expected-version> [results-tsv]}"
RESULTS="${2:-}"

INSTALL_BIN="/usr/local/bin/phvalheim-client"
INSTALL_APP="/Applications/PhValheim Client.app"
HANDLER="$INSTALL_APP/Contents/MacOS/PhValheim Client"
PLIST="$INSTALL_APP/Contents/Info.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fails=0
checks=0

emit() { [ -n "$RESULTS" ] && printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"; return 0; }

ok()   { checks=$((checks+1)); echo "  PASS  $1"; emit PASS "$1" "${2:-}"; }
warn() { checks=$((checks+1)); echo "  WARN  $1"; echo "        $2"; emit WARN "$1" "$2"; }
info() { echo "  INFO  $1: $2"; emit INFO "$1" "$2"; }
fail() {
	checks=$((checks+1)); fails=$((fails+1))
	echo "  FAIL  $1"
	echo "        expected: $2"
	echo "        actual:   $3"
	emit FAIL "$1" "expected $2, got $3"
}

expect() { if [ "$2" = "$3" ]; then ok "$1" "$3"; else fail "$1" "$2" "$3"; fi; }

echo
echo "=== PhValheim Client macOS verification ==="
echo "Expected version: $expectVersion"
echo "Hardware:         $(uname -m) / $(sw_vers -productName) $(sw_vers -productVersion)"
echo

# ── 1-2. the client binary exists and is universal ─────────────────────────────
if [ -f "$INSTALL_BIN" ]; then
	ok "Client binary installed" "$INSTALL_BIN"

	archs=$(lipo -archs "$INSTALL_BIN" 2>/dev/null || echo "")
	case "$archs" in
		*x86_64*arm64*|*arm64*x86_64*) ok "Client binary is universal" "$archs" ;;
		*) fail "Client binary is universal" "x86_64 and arm64" "${archs:-not a Mach-O}" ;;
	esac

	# ── 3. every slice carries a signature ─────────────────────────────────────
	for a in x86_64 arm64; do
		if codesign -dv --arch "$a" "$INSTALL_BIN" 2>&1 | grep -q '^Signature'; then
			ok "Client $a slice is signed"
		else
			fail "Client $a slice is signed" "a signature" "none"
		fi
	done

	# ── 4. the signature is internally consistent ──────────────────────────────
	if csout=$(codesign --verify --strict --verbose=2 "$INSTALL_BIN" 2>&1); then
		ok "Client signature verifies (--strict)"
	else
		fail "Client signature verifies (--strict)" "valid" "$(echo "$csout" | head -1)"
	fi

	# ── 5. no quarantine flag survived the install ─────────────────────────────
	if xattr "$INSTALL_BIN" 2>/dev/null | grep -q com.apple.quarantine; then
		fail "No quarantine xattr on client" "absent" "present"
	else
		ok "No quarantine xattr on client"
	fi

	# ── 6. IT ACTUALLY RUNS. ───────────────────────────────────────────────────
	# Zero args is a no-side-effect path: Arguments.cs prints usage and bails
	# before touching Steam, the network or the filesystem. If AMFI rejects the
	# code signature the kernel SIGKILLs us instead and rc is 137.
	set +e
	runout=$("$INSTALL_BIN" 2>&1); rc=$?
	set -e
	case "$runout" in
		*"No arguments passed"*) ok "Client executes on $(uname -m)" "rc=$rc, printed usage" ;;
		*)
			if [ "$rc" -ge 128 ]; then
				fail "Client executes on $(uname -m)" "usage text" "killed by signal $((rc-128)) -- AMFI rejected the signature"
			else
				fail "Client executes on $(uname -m)" "usage text" "rc=$rc: $(echo "$runout" | head -1)"
			fi
			;;
	esac

	# ── 7. the URL parse path runs and rejects junk ────────────────────────────
	set +e
	urlout=$("$INSTALL_BIN" 'phvalheim:///?' 2>&1)
	set -e
	case "$urlout" in
		*"malformed phvalheim URL"*) ok "Client rejects a malformed phvalheim:// URL" ;;
		*) fail "Client rejects a malformed phvalheim:// URL" "malformed URL error" "$(echo "$urlout" | head -1)" ;;
	esac
else
	fail "Client binary installed" "$INSTALL_BIN" "missing"
fi

# ── 8-11. the .app URL handler ─────────────────────────────────────────────────
if [ -d "$INSTALL_APP" ]; then
	ok "App bundle installed" "$INSTALL_APP"

	if [ -f "$HANDLER" ]; then
		ok "URL handler binary present"

		# 2.0.12 shipped this arm64-only next to a universal client, so Intel
		# Macs had no working phvalheim:// handler at all. Assert both slices.
		harchs=$(lipo -archs "$HANDLER" 2>/dev/null || echo "")
		case "$harchs" in
			*x86_64*arm64*|*arm64*x86_64*) ok "URL handler is universal" "$harchs" ;;
			*) fail "URL handler is universal" "x86_64 and arm64" "${harchs:-not a Mach-O}" ;;
		esac

		if codesign --verify --strict "$HANDLER" 2>/dev/null; then
			ok "URL handler signature verifies"
		else
			fail "URL handler signature verifies" "valid" "invalid or unsigned"
		fi
	else
		fail "URL handler binary present" "$HANDLER" "missing"
	fi

	expect "Info.plist CFBundleVersion matches build" \
		"$expectVersion" \
		"$(defaults read "$PLIST" CFBundleVersion 2>/dev/null || echo unreadable)"

	if plutil -extract CFBundleURLTypes json -o - "$PLIST" 2>/dev/null | grep -q phvalheim; then
		ok "Info.plist declares the phvalheim:// scheme"
	else
		fail "Info.plist declares the phvalheim:// scheme" "CFBundleURLTypes with phvalheim" "absent"
	fi
else
	fail "App bundle installed" "$INSTALL_APP" "missing"
fi

# ── 12. Launch Services actually knows about the scheme ────────────────────────
if [ -x "$LSREGISTER" ]; then
	if "$LSREGISTER" -dump 2>/dev/null | grep -q 'phvalheim:'; then
		ok "phvalheim:// is registered with Launch Services"
	else
		fail "phvalheim:// is registered with Launch Services" "a phvalheim: binding" "not in the LS database"
	fi
else
	warn "phvalheim:// is registered with Launch Services" "lsregister not found at the expected path"
fi

# ── 13. Gatekeeper, on a quarantined copy ──────────────────────────────────────
# A CI-downloaded artifact carries no quarantine bit, so the default run silently
# tests the easy case. Reproduce what a browser download looks like instead.
# Recorded as INFO, not a gate: the build is ad-hoc signed, not Developer ID, so
# Gatekeeper is EXPECTED to reject it -- that is exactly why macinstall.sh strips
# the xattr. This check exists to notice if that story ever changes.
if [ -f "$INSTALL_BIN" ]; then
	qtmp=$(mktemp -d)
	cp "$INSTALL_BIN" "$qtmp/phvalheim-client"
	xattr -w com.apple.quarantine "0081;00000000;Safari;" "$qtmp/phvalheim-client" 2>/dev/null || true
	spctlout=$(spctl -a -t exec -vv "$qtmp/phvalheim-client" 2>&1 | tr '\n' ' ')
	info "Gatekeeper verdict on a quarantined copy" "${spctlout:-no output}"
	rm -rf "$qtmp"
fi

echo
echo "=== $((checks - fails))/$checks checks passed ==="
if [ "$fails" -gt 0 ]; then
	echo "=== $fails FAILED ==="
	exit 1
fi
exit 0
