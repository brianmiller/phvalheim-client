#!/usr/bin/env python3
"""Smoke test for the CLIENT, as opposed to the installer.

Until now every automated check in this repo tested the .msi. Nothing ever ran
the program. `test_install_matrix.py` proves the exe is installed; it never
proves it starts.

This runs the ACTUAL shipped win-x64 exe under wine and exercises the argument
handler -- the code path every `phvalheim://` click enters first, and the only
part of the client that can be tested hermetically. No server, no Steam, no
Valheim.

Scope, stated so nobody mistakes a green run for more than it is:

  COVERED     startup, version reporting, usage output, and all four malformed
              URL paths in Arguments.argHandler, plus "does not hang on stdin"
  NOT COVERED anything after a well-formed launch URL -- Platform.State.init,
              PhValheimPrep, Downloader, Syncer, Launcher. Those need a real
              server and a real Steam install. They remain untested.

Usage:
    test_client_smoke.py <path-to-exe> <expected-version>
"""

import os
import re
import subprocess
import sys

checks = 0
fails = 0
# The client asks "Press Enter key to exit" on every failure path, so stdin
# must be closed or the process blocks forever. A per-case timeout turns a
# future hang into a FAIL instead of a stuck build.
CASE_TIMEOUT = 120


def ok(msg):
    global checks
    checks += 1
    print(f"  PASS  {msg}", flush=True)


def bad(msg, expected, actual):
    global checks, fails
    checks += 1
    fails += 1
    print(f"  FAIL  {msg}\n        expected: {expected}\n        actual:   {actual}", flush=True)


def run_client(exe, args):
    env = dict(os.environ)
    env.update({"WINEDEBUG": "-all", "WINEPREFIX": env.get("WINEPREFIX", "/tmp/wp-smoke"),
                "XDG_RUNTIME_DIR": env.get("XDG_RUNTIME_DIR", "/tmp/xdg")})
    try:
        p = subprocess.run(["wine", exe] + args, env=env, timeout=CASE_TIMEOUT,
                           stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return p.returncode, p.stdout.decode(errors="replace")
    except subprocess.TimeoutExpired:
        return None, f"<timed out after {CASE_TIMEOUT}s>"


def b64url(payload):
    """The client takes phvalheim://?<base64 of 'command?a?b?...'>."""
    import base64
    return "phvalheim://?" + base64.b64encode(payload.encode()).decode()


def assert_no_crash(label, out):
    """A .NET stack trace reaching the user is a defect regardless of the
    message above it."""
    markers = ("Unhandled exception", "at System.", "System.NullReferenceException",
               "System.IndexOutOfRangeException", "System.FormatException")
    hit = [m for m in markers if m in out]
    if hit:
        bad(f"{label}: no unhandled .NET exception", "a clean error message",
            f"{hit} in output")
    else:
        ok(f"{label}: no unhandled .NET exception")


def case(exe, label, args, must_contain):
    rc, out = run_client(exe, args)
    if rc is None:
        # The client calls Console.ReadLine() on every failure path. With stdin
        # closed that returns immediately; if it ever blocks anyway, that is a
        # real regression for anyone launching it from a URL handler.
        bad(f"{label}: exits without waiting on stdin", "an exit", out)
        return out
    ok(f"{label}: exits without waiting on stdin")
    for needle in must_contain:
        if needle in out:
            ok(f"{label}: says {needle!r}")
        else:
            bad(f"{label}: says {needle!r}", needle, out.strip()[-200:] or "<no output>")
    assert_no_crash(label, out)
    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    exe, expect_version = sys.argv[1], sys.argv[2]
    if not os.path.exists(exe):
        print(f"  FAIL  exe not found: {exe}")
        return 1

    print(f"Client smoke test: {os.path.basename(exe)} (expecting {expect_version})")
    print("=" * 64)

    print("\n-- no arguments --")
    out = case(exe, "no args", [],
               ["PhValheim Client Version", "Usage:", "ERROR: No arguments passed."])

    # Ties the BUILT BINARY to the csproj. The retired .vdproj drifted to
    # 2.0.12 while the csproj said 2.0.13; this is the check that would have
    # caught the same drift in the app itself.
    m = re.search(r"PhValheim Client Version ([0-9][^\s]*)", out)
    if not m:
        bad("reported version is readable", f"'PhValheim Client Version {expect_version}'",
            out.strip()[:200])
    else:
        got = m.group(1)
        if got == expect_version:
            ok(f"reported version matches the csproj ({got})")
        else:
            bad("reported version matches the csproj", expect_version, got)

    print("\n-- malformed phvalheim:// URLs --")
    # Each of these is a distinct early-return in Arguments.argHandler.
    case(exe, "empty query", ["phvalheim:///?"], ["malformed phvalheim URL"])
    case(exe, "not base64", ["phvalheim://?not-valid-base64!!"], ["malformed phvalheim URL"])
    case(exe, "no query at all", ["phvalheim://"], ["malformed phvalheim URL"])
    case(exe, "base64 but one field", [b64url("launch")], ["malformed phvalheim URL"])
    case(exe, "launch missing fields", [b64url("launch?World?pw")], ["malformed phvalheim URL"])
    case(exe, "textures missing fields", [b64url("textures?World")], ["malformed phvalheim URL"])

    print("\n" + "-" * 64)
    print("COVERAGE NOTE: this exercises argument handling only. Everything past")
    print("a well-formed launch URL -- Platform.State.init, PhValheimPrep,")
    print("Downloader, Syncer, Launcher -- needs a real server and Steam install")
    print("and is still completely untested.")
    print("=" * 64)
    if fails == 0:
        print(f"OK: {checks} client smoke checks passed")
        return 0
    print(f"FAILED: {fails} of {checks} client smoke checks failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
