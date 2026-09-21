#!/usr/bin/env python3
"""Regression guard for the NON-Flatpak Linux packages.

Flatpak.cs is shared code, not Flatpak-only code. Platform.cs and Launcher.cs
now call Sandbox.Flatpak.HostCommand() and HostProcessRunning()
unconditionally, and outside a sandbox those must behave exactly as the
original inline Process.Start() calls did. If the pass-through is wrong, the
Flatpak can be perfectly green while the .deb, .rpm and .tar.gz -- which have
no gates of their own -- are silently broken for every user.

So this runs the same published linux-x64 binary those packages ship, with no
flatpak involved at all, against the same stub Steam and stub Valheim the
Flatpak tests use, and asserts the same observable outcomes.

Every check here looks for POSITIVE evidence. An earlier draft asserted the
absence of error strings ("Steam isn't installed" not in output), which passes
just as happily when the process dies before printing anything at all -- and
that is exactly what happened the first time it ran.

usage: test_native_passthrough.py <path-to-linux-x64-binary>
"""

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_flatpak_runtime as T  # noqa: E402  (shared stub host + fake server)

checks = 0
fails = 0


def chk(label, cond, detail=""):
    global checks, fails
    checks += 1
    if cond:
        print(f"  PASS  {label}", flush=True)
    else:
        fails += 1
        print(f"  FAIL  {label}\n        {detail}", flush=True)


def run(exe, url):
    p = subprocess.run([exe, url], capture_output=True, timeout=300,
                       stdin=subprocess.DEVNULL)
    return p.returncode, p.stdout.decode(errors="replace"), p.stderr.decode(errors="replace")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    exe = sys.argv[1]
    if not os.path.exists(exe):
        print(f"  FAIL  binary not found: {exe}")
        return 1

    print("Native (non-Flatpak) pass-through: the binary the .deb/.rpm/.tgz ship")
    print("=" * 70)

    chk("this process is not in a flatpak sandbox", not os.path.exists("/.flatpak-info"),
        "/.flatpak-info exists; run this outside a sandbox")

    valheim_dir = T.build_fake_host()
    zip_path = T.FAKE / f"{T.WORLD}.zip"
    T.build_world_zip(zip_path)
    srv, port = T.start_fake_server(zip_path, "unused")

    try:
        # ---- vanilla: straight to Steam with +connect ----
        print("\n-- vanilla world --")
        T.clear_logs()
        rc, out, err = run(exe, T.launch_url(T.WORLD, port, vanilla=True))

        # Positive evidence the client got past Steam discovery and prep.
        chk("the client ran far enough to prepare its directories",
            "PhValheim root" in out, f"rc={rc} stdout={out[-300:]!r} stderr={err[:300]!r}")
        chk("the Valheim install was located",
            "Valheim root directory was found" in out,
            f"rc={rc} stdout={out[-300:]!r} stderr={err[:300]!r}")
        chk("no unhandled .NET exception", "Unhandled exception" not in out + err,
            (out + err)[-300:])

        got = T.wait_for_text(T.STEAM_LOG, "-applaunch", timeout=90)
        log = T.STEAM_LOG.read_text() if T.STEAM_LOG.exists() else "<stub never invoked>"
        chk("Steam was invoked on the host with -applaunch", got, log)
        chk("Steam was given Valheim's app id and connect address",
            got and "892970" in log and f"{T.SRV_HOST}:2456" in log, log)

        # ---- modded: sync, then exec the game with the doorstop env ----
        print("\n-- modded world --")
        T.clear_logs()
        rc, out, err = run(exe, T.launch_url(T.WORLD, port, vanilla=False))
        chk("no unhandled .NET exception", "Unhandled exception" not in out + err,
            (out + err)[-300:])

        rec = T.wait_for_json(T.VALHEIM_LOG, timeout=90)
        if rec is None:
            chk("Valheim was executed on the host", False,
                f"rc={rc} stdout={out[-400:]!r} stderr={err[:400]!r}")
            return 1
        chk("Valheim was executed on the host", True)

        env = rec["env"]
        chk("DOORSTOP_ENABLED is set", env.get("DOORSTOP_ENABLED") == "1",
            env.get("DOORSTOP_ENABLED"))
        chk("DOORSTOP_TARGET_ASSEMBLY points at the synced preloader",
            "BepInEx.Preloader.dll" in env.get("DOORSTOP_TARGET_ASSEMBLY", ""),
            env.get("DOORSTOP_TARGET_ASSEMBLY"))
        chk("LD_PRELOAD injects doorstop",
            "libdoorstop_x64.so" in env.get("LD_PRELOAD", ""), env.get("LD_PRELOAD"))
        chk("LD_LIBRARY_PATH is the game's doorstop_libs",
            env.get("LD_LIBRARY_PATH") == str(Path(valheim_dir) / "doorstop_libs"),
            env.get("LD_LIBRARY_PATH"))
        chk("the game ran in its own directory", rec["cwd"] == str(valheim_dir),
            rec["cwd"])
        chk("argv is exactly the game plus -console", rec["argv"][1:] == ["-console"],
            rec["argv"])

        # Nothing flatpak-shaped may appear on a native run.
        chk("no flatpak-spawn wrapper leaked into the native launch",
            "flatpak" not in " ".join(rec["argv"]).lower(), rec["argv"])
    finally:
        srv.shutdown()

    print("\n" + "=" * 70)
    if fails == 0:
        print(f"OK: {checks} native pass-through checks passed")
        return 0
    print(f"FAILED: {fails} of {checks} native pass-through checks failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
