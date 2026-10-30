#!/bin/bash
# Oracle test: the launch window stays open until Valheim exits, and the notice it prints is
# TRUE -- closing the window really does leave the game running.
#
# WHAT WAS WRONG. Main.cs printed "This window closes on its own in 10 seconds" and slept. The
# window's lifetime had nothing to do with the player's session: it vanished ten seconds in,
# taking the launch log with it, so a crash two minutes later had nothing left on screen.
#
# THE PART WORTH TESTING IS THE CLAIM, NOT THE WAIT. Brian asked for a notice saying it is safe
# to close the window. On Windows that is free -- Steam starts the game. On Linux it is
# deliberate -- we go through setsid. On macOS it was FALSE: the .app URL handler opens a
# Terminal window to run the client (builders/url-handler.swift), macOS SIGHUPs the foreground
# process group when a Terminal window closes, and Valheim is our direct child there. The
# notice would have told players to do the one thing that killed their session.
#
# So part 3 actually sends SIGHUP to a process launched through the same `trap '' HUP; exec`
# construction and checks it is still alive. A source-level check that the string is present
# cannot tell whether ignored-signal inheritance works, and inheritance across exec is the
# entire mechanism.
#
# --control IS ONLY MEANINGFUL BEFORE THE FIX IS COMMITTED. It builds the tree from HEAD, so
# while you are developing it shows you the failures your change is fixing -- and the moment
# you commit, HEAD *is* the fixed code and the control run passes. A passing control does NOT
# mean the suite has stopped discriminating; it almost always just means the fix has landed.
#
# What proves the suite still bites is MUTATION: break the line and check this notices. The
# "Prove the oracles can still fail" step in .github/workflows/macos-verify.yml does exactly
# that, which is why it does not use this flag.
#
# Usage:  bash dev_tools/test-launch-window-waits.sh [--control]

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

CONTROL=0
[ "$1" = "--control" ] && CONTROL=1

SRC="$REPO"
if [ "$CONTROL" = "1" ]; then
	SRC=$(mktemp -d)
	git -C "$REPO" archive HEAD | tar -x -C "$SRC" 2>/dev/null \
		|| { echo "FATAL: cannot export HEAD"; exit 1; }
	echo "== CONTROL RUN: the tree as it is in HEAD. Failures below are the POINT. =="
fi

PASS=0; FAIL=0
pass(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
fail(){ echo "  FAIL: $1"; [ -n "$2" ] && echo "        $2"; FAIL=$((FAIL+1)); }

M="$SRC/Main.cs"
L="$SRC/Launcher.cs"
G="$SRC/Game.cs"

# Comment-stripped copies. Every marker below is measured against these, because the comments
# in these files quote the old strings verbatim while explaining why they went -- "This used to
# print 'This window closes on its own in 10 seconds'" would satisfy a grep for the very thing
# the fix removed.
code(){ grep -vE '^[[:space:]]*(//|///)' "$1" 2>/dev/null; }

echo
echo "== part 1: the window's lifetime is the game's, not a timer =="

if [ ! -f "$G" ]; then
	fail "Game.cs does not exist" "nothing can observe the game's lifetime"
else
	pass "Game.cs exists"
fi

n=$(code "$M" | grep -c 'closes on its own in 10 seconds')
[ "$n" = "0" ] \
	&& pass "the 10-second self-close message is gone ($n)" \
	|| fail "the window still promises to close on a timer ($n)"

n=$(code "$M" | grep -c 'Thread.Sleep(10000)')
[ "$n" = "0" ] \
	&& pass "the 10-second sleep after launch is gone ($n)" \
	|| fail "the post-launch sleep is still there ($n)"

n=$(code "$M" | grep -c 'Game.WaitForExit()')
[ "$n" = "1" ] \
	&& pass "Main waits on the game instead ($n call)" \
	|| fail "$n calls to Game.WaitForExit() in Main -- want 1"

# An unobservable game must NOT be reported as a clean exit, and must not close the window
# either. This is the Flatpak case: Steam runs Valheim on the host, outside our process
# namespace, so IsRunning() is blind there and says "no" for a game that is running fine.
# SCOPED TO AFTER THE LAUNCH. Main.cs calls PressEnterToExit on six earlier error paths, so a
# whole-file grep passed against HEAD -- where there is no post-launch wait at all. The
# assertion is about the fallback for an unobservable game, which only exists below the Launch
# call, so that is the only region worth reading.
postLaunch=$(code "$M" | sed -n '/Launcher.PhValheim.Launch/,$p')
if [ -z "$postLaunch" ]; then
	fail "could not find the launch call in Main.cs" "extraction is stale"
elif printf '%s' "$postLaunch" | grep -q 'Thread.Sleep(30000)'; then
	pass "when it cannot tell, the window shows a bounded warning instead of accumulating"
else
	fail "no fallback when the game is never seen" \
	     "the window would close instantly on a Flatpak, where the game is outside our namespace"
fi

echo
echo "== part 2: the notice says the window is safe to close =="

code "$M" | grep -qi 'close this window at any time' \
	&& pass "the player is told they may close the window" \
	|| fail "no 'safe to close' notice" "this is the thing that was asked for"

code "$M" | grep -qi 'keeps running' \
	&& pass "and told the game keeps running if they do" \
	|| fail "the notice does not say the game survives"

echo
echo "== part 3: THE CLAIM -- a game launched this way survives a hangup =="

# Pull the exact sh construction out of the real Launcher and run a sleeper through it, then
# SIGHUP the process group the way a closing Terminal window does.
# Matched as a FIXED STRING up to the exec, not as a regex over the whole argument. In the C#
# source the quotes are backslash-escaped -- the file literally contains `exec \"$@\"` -- and
# the first version of this grep looked for `exec "$@"`, found nothing, and reported the fix as
# absent on a tree that had it. The shape being asserted is "trap, then exec"; the quoting of
# $@ is C#'s business and is covered by the compile in part 5.
trapline=$(code "$L" | grep -F "trap '' HUP; exec" | head -1 | sed 's/^[[:space:]]*//')
if [ -z "$trapline" ]; then
	fail "Launcher does not launch the macOS game with SIGHUP ignored" \
	     "closing the Terminal window the .app opens would kill the player's session"
else
	pass "Launcher execs the macOS game with SIGHUP ignored ($trapline)"
fi

# Behavioural: same shape, real signal. setsid gives the child its own process group so the
# kill below cannot reach back into this script -- an earlier version of this test killed its
# own process group and reported the harness's death as the product's.
probe(){
	local trapArg="$1" pgid child
	setsid /bin/sh -c "$trapArg exec \"\$@\"" sh /bin/sleep 30 &
	child=$!
	# Wait for it to really be the sleep, not still sh. Without this the kill can land before
	# the exec and prove nothing about inheritance across it.
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		if ps -o args= -p "$child" 2>/dev/null | grep -q 'sleep 30'; then break; fi
		sleep 0.2
	done
	pgid=$(ps -o pgid= -p "$child" 2>/dev/null | tr -d ' ')
	[ -n "$pgid" ] || { echo "NOPGID"; return; }
	kill -HUP -- "-$pgid" 2>/dev/null
	sleep 0.5
	if kill -0 "$child" 2>/dev/null; then echo "SURVIVED"; else echo "DIED"; fi
	kill -9 -- "-$pgid" 2>/dev/null
	wait "$child" 2>/dev/null
}

got=$(probe "trap '' HUP;")
case "$got" in
	SURVIVED) pass "a process exec'd after trap '' HUP survives SIGHUP to its group" ;;
	DIED)     fail "the trap did NOT survive the exec" \
	               "then the notice is a lie on macOS and the player loses their session" ;;
	*)        fail "the probe could not run" "got: $got" ;;
esac

# THE CONTROL FOR THE PROBE. Without the trap the same sleeper must die -- otherwise the test
# above proves only that SIGHUP does not kill sleep on this box, and would pass with the fix
# removed.
got=$(probe "")
case "$got" in
	DIED)     pass "and without the trap the same process DIES -- so the probe is measuring the trap" ;;
	SURVIVED) fail "the no-trap control also survived" \
	               "this box does not kill on SIGHUP, so part 3 proves nothing here" ;;
	*)        fail "the control probe could not run" "got: $got" ;;
esac

echo
echo "== part 4: waiting by name, because no handle works =="

# The launcher's child is Steam on Windows and setsid on Linux; both exit at once, so a
# WaitForExit() on the handle would return immediately and close the window.
if [ -f "$G" ]; then
	code "$G" | grep -q 'GetProcessesByName' \
		&& pass "Game reads the process table rather than a handle" \
		|| fail "Game does not look the process up by name" \
		        "a handle to Steam or to setsid exits immediately"

	code "$G" | grep -q 'valheim.x86_64' \
		&& pass "the Linux binary name is matched" \
		|| fail "valheim.x86_64 is not among the names searched"

	# Two phases. A single-phase wait returns before the game has even appeared.
	appear=$(code "$G" | grep -c 'appearSeconds')
	[ "${appear:-0}" -ge 2 ] \
		&& pass "there is an appear phase before the exit phase ($appear references)" \
		|| fail "no appear phase" "polling straight after launch answers 'not running' and closes the window"
fi

echo
echo "== part 5: it compiles =="

# LOCAL dotnet first, docker only as a fallback.
#
# CI has the SDK preinstalled, and pulling mcr.microsoft.com/dotnet/sdk:9.0 there costs about
# a gigabyte to answer a question the runner can already answer. The fallback stays for boxes
# with docker and no SDK.
#
# Neither available is a SKIP that says so. It must never read as a pass: the compile is what
# proves the ArgumentList shape in part 3 is real C# and not just a string that greps well.
out=""
buildWith=""

# TRY LOCAL, THEN FALL BACK -- in that order, and the fallback is not optional.
#
# The project targets net9.0 and this dev box has SDK 8.0.131, which cannot build it: switching
# to "local dotnet if present" turned a passing part 5 into "1 Error(s)" and I only saw it
# because I re-ran the test. A version check would work too, but trying the build and reading
# the result cannot be wrong about what this SDK can actually compile.
if command -v dotnet >/dev/null 2>&1; then
	out=$( cd "$SRC" && dotnet build -v q --nologo 2>&1 | tail -6 )
	if printf '%s' "$out" | grep -q '0 Error(s)'; then
		buildWith="local dotnet $(dotnet --version 2>/dev/null)"
	fi
fi

if [ -z "$buildWith" ] && command -v docker >/dev/null 2>&1; then
	dockerOut=$(docker run --rm -v "$SRC":/src -w /src mcr.microsoft.com/dotnet/sdk:9.0 \
	        bash -c 'dotnet build -v q --nologo 2>&1 | tail -6' 2>&1)
	# Only adopt the docker result if it got further. A local SDK that is merely too old must
	# not mask a real compile error, so a docker run that ALSO fails leaves the local output
	# in place as the thing to report.
	if printf '%s' "$dockerOut" | grep -q '0 Error(s)'; then
		out="$dockerOut"
		buildWith="docker dotnet/sdk:9.0"
	elif [ -z "$out" ]; then
		out="$dockerOut"
		buildWith="docker dotnet/sdk:9.0"
	fi
fi

# Neither tool present at all: name it and fail, rather than reporting a pass for a compile
# that never happened.
if [ -z "$buildWith" ] && [ -z "$out" ]; then
	buildWith=""
elif [ -z "$buildWith" ]; then
	buildWith="dotnet/docker (both failed)"
fi

if [ -z "$buildWith" ]; then
	fail "no dotnet and no docker -- the project was NOT compiled" \
	     "part 3 only checked that a string is present; nothing proved it is valid C#"
elif printf '%s' "$out" | grep -q '0 Error(s)'; then
	pass "the project builds with 0 errors ($buildWith)"
else
	fail "the project does not build ($buildWith)" "$(printf '%s' "$out" | tail -4)"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$CONTROL" = "1" ] && rm -rf "$SRC"
[ "$FAIL" -eq 0 ] || exit 1
