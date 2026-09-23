#!/bin/bash
#
# Exercise the phvalheim:// handler for real: hand a URL to Launch Services and
# follow it all the way down to the argv the client receives.
#
#   open phvalheim://...
#     -> Launch Services routes the scheme to /Applications/PhValheim Client.app
#       -> NSApplication delivers a GetURL Apple Event
#         -> url-handler.swift writes /tmp/phvalheim-launch-<pid>.sh
#           -> `open -a Terminal` on that script
#             -> the script runs /usr/local/bin/phvalheim-client "<url>"
#
# verify_macos.sh proves the scheme is REGISTERED. Registration is not delivery:
# every link in the chain above can be correct in isolation and still drop the
# URL. This checks delivery.
#
# Needs a GUI (Aqua) session. Hosted macos-15 runners have one -- measured, see
# the runner-probe job. Without one this degrades to a WARN rather than a false
# failure, because a headless box cannot answer the question either way.
#
# The client binary is swapped for an argv-recording shim for the duration, then
# restored. That is deliberate: this script tests the PLUMBING. Whether the real
# binary runs is verify_macos.sh's job, and it already answers it.
#
# Usage: verify_macos_gui.sh [results-tsv]

set -u

RESULTS="${1:-}"

INSTALL_BIN="/usr/local/bin/phvalheim-client"
INSTALL_APP="/Applications/PhValheim Client.app"
ARGV_LOG="/tmp/phvalheim-argv.log"
STASH="/tmp/phvalheim-client.real"

fails=0
checks=0

# macOS ships no timeout(1). Anything here that touches the window server or
# Launch Services can block forever on a runner -- there is no one to dismiss a
# consent dialog -- and an unbounded call took a whole job slot hostage once.
# perl is always present and its alarm survives exec, so this kills the real
# process rather than an orphaned wrapper.
bounded() { # bounded <seconds> <cmd...>
	perl -e 'alarm shift; exec @ARGV or exit 127' "$@"
}

# Breadcrumb before every call that could hang, so a future hang is located by
# reading the log instead of by bisecting the script.
step() { echo "  ..$1"; }

emit() { [ -n "$RESULTS" ] && printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"; return 0; }
ok()   { checks=$((checks+1)); echo "  PASS  $1"; emit PASS "$1" "${2:-}"; }
warn() { checks=$((checks+1)); echo "  WARN  $1"; echo "        $2"; emit WARN "$1" "$2"; }
fail() {
	checks=$((checks+1)); fails=$((fails+1))
	echo "  FAIL  $1"; echo "        $2"; emit FAIL "$1" "$2"
}

echo
echo "=== phvalheim:// activation ==="
echo

# ── Is there a GUI session to activate into? ───────────────────────────────────
session=$(launchctl managername 2>/dev/null || echo unknown)
if [ "$session" != "Aqua" ]; then
	warn "GUI (Aqua) session available" \
	     "launchctl managername = $session -- activation cannot be tested here, only registration"
	echo
	echo "=== skipped: no Aqua session ==="
	exit 0
fi
ok "GUI (Aqua) session available" "launchctl managername = Aqua"

# ── Install the argv recorder ──────────────────────────────────────────────────
restore() {
	if [ -f "$STASH" ]; then
		sudo mv -f "$STASH" "$INSTALL_BIN"
		sudo chmod 755 "$INSTALL_BIN"
		echo "  ..restored the real client binary"
	fi
}
trap restore EXIT

if [ ! -f "$INSTALL_BIN" ]; then
	fail "Client binary is installed" "$INSTALL_BIN is missing -- run macinstall.sh install first"
	exit 1
fi

sudo mv "$INSTALL_BIN" "$STASH"
sudo tee "$INSTALL_BIN" >/dev/null <<'SHIM'
#!/bin/bash
printf '%s\n' "$@" >> /tmp/phvalheim-argv.log
SHIM
sudo chmod 755 "$INSTALL_BIN"

# ── Negative control ───────────────────────────────────────────────────────────
# Clear the evidence first and prove it is gone. Without this, a leftover file
# from an earlier run would make every check below pass for the wrong reason --
# the whole point is that the nonce we are about to send is what shows up.
rm -f "$ARGV_LOG" /tmp/phvalheim-launch-*.sh
if [ -e "$ARGV_LOG" ]; then
	fail "Negative control: no argv log before the trigger" "$ARGV_LOG still exists"
	exit 1
fi
ok "Negative control: no argv log before the trigger"

# Bash builtins only. `tr -dc 'a-f0-9' </dev/urandom | head -c 12` hung this
# step for the full 5-minute cap on macos-15: BSD tr buffers its output, so it
# keeps draining /dev/urandom looking for enough matching bytes to flush, and
# head never gets its 12 -- while $( ) waits on every process in the pipeline.
# Uniqueness within one run is all this needs, and the negative control above
# already guarantees the log is fresh.
step "generating nonce"
nonce="ciprobe${RANDOM}${RANDOM}$$"
URL="phvalheim://activation?$nonce"

# ── Fire it the way a browser would ────────────────────────────────────────────
step "triggering: open $URL"
bounded 20 open "$URL" 2>/dev/null || echo "  ..open(1) returned non-zero or timed out; continuing to the observations"
step "open(1) returned"

waitfor() { # waitfor <seconds> <test-command...>
	local n="$1"; shift
	local i=0
	while [ "$i" -lt "$n" ]; do
		if bounded 5 "$@" >/dev/null 2>&1; then return 0; fi
		sleep 1; i=$((i+1))
	done
	return 1
}

# ── 1. did the handler app come up? ────────────────────────────────────────────
step "check 1: waiting for the handler process"
if waitfor 15 pgrep -f 'PhValheim Client.app/Contents/MacOS'; then
	ok "Launch Services started the handler app"
else
	fail "Launch Services started the handler app" \
	     "no 'PhValheim Client' process appeared within 15s of open(1)"
fi

# ── 2. did the Apple Event arrive with our URL? ────────────────────────────────
# url-handler.swift only writes this file from inside application(_:open:), so
# its existence IS the proof that the GetURL event was delivered and parsed.
step "check 2: waiting for the launch script"
# External command, not a shell function: waitfor runs its argument through
# bounded(), which execs, and exec cannot exec a function.
if waitfor 15 bash -c 'ls /tmp/phvalheim-launch-*.sh'; then
	script=$(ls -t /tmp/phvalheim-launch-*.sh 2>/dev/null | head -1)
	ok "GetURL Apple Event delivered to the handler" "wrote $(basename "$script")"

	# ── 3. is it OUR url, not just any url? ────────────────────────────────────
	if grep -q "$nonce" "$script" 2>/dev/null; then
		ok "URL survived Launch Services intact" "nonce $nonce present in the launch script"
	else
		fail "URL survived Launch Services intact" \
		     "launch script does not contain $nonce: $(head -2 "$script" | tr '\n' ' ')"
	fi
else
	fail "GetURL Apple Event delivered to the handler" \
	     "no /tmp/phvalheim-launch-*.sh within 15s -- the app launched but never got the URL"
fi

# ── 4. did Terminal actually get opened? ───────────────────────────────────────
step "check 4: waiting for Terminal.app"
if waitfor 15 pgrep -x Terminal; then
	ok "Handler opened Terminal.app"
else
	fail "Handler opened Terminal.app" "no Terminal process within 15s"
fi

# ── 5. the whole chain: did the client receive the URL as argv? ────────────────
step "check 5: waiting for argv delivery"
if waitfor 30 grep -q "$nonce" "$ARGV_LOG"; then
	ok "Client received the URL as argv" "$(grep -m1 "$nonce" "$ARGV_LOG")"
else
	if [ -f "$ARGV_LOG" ]; then
		fail "Client received the URL as argv" \
		     "client was invoked but without our nonce: $(head -2 "$ARGV_LOG" | tr '\n' ' ')"
	else
		fail "Client received the URL as argv" \
		     "client was never invoked -- Terminal did not run the launch script within 30s"
	fi
fi

# ── tidy ───────────────────────────────────────────────────────────────────────
# Signals, not Apple Events. `osascript -e 'tell application "Terminal" to quit'`
# needs TCC Automation consent, and with no one to click the dialog it can block
# forever. Run 35813131570 hung in this step and produced no retrievable log, so
# the culprit was never pinned down; osascript was the leading suspect and is
# the one call here that was both unbounded and consent-gated. The breadcrumbs
# above exist so the next hang does not have to be guessed at.
step "cleanup"
pkill -x Terminal 2>/dev/null || true
pkill -f 'PhValheim Client.app/Contents/MacOS' 2>/dev/null || true
rm -f "$ARGV_LOG" /tmp/phvalheim-launch-*.sh
step "cleanup done"

echo
echo "=== $((checks - fails))/$checks activation checks passed ==="
[ "$fails" -gt 0 ] && { echo "=== $fails FAILED ==="; exit 1; }
exit 0
