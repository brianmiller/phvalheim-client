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
import re
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


def run(exe, url, extra_env=None):
    env = dict(os.environ)
    if extra_env:
        env.update(extra_env)
    p = subprocess.run([exe, url], capture_output=True, timeout=300,
                       stdin=subprocess.DEVNULL, env=env)
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
        #
        # Re-anchored when the console output moved behind Ui.cs. Both of these used to pin
        # lines that are now DEVELOPER DETAIL, printed only under PHVALHEIM_VERBOSE -- the
        # absolute paths ("PhValheim root: /home/...", "Valheim root directory was found: ...").
        # A player does not need a path to learn that a directory is ready; they need the
        # verdict, and the verdict is what these assert on now.
        #
        # Label AND status on ONE line, via a regex rather than two substring checks. "found"
        # appears elsewhere in the output, so an independent `"found" in out` would pass even
        # if the Valheim step had failed -- the pairing is the whole point.
        chk("the client ran far enough to prepare its directories",
            re.search(r"PhValheim folders \.+ ready", out) is not None,
            f"rc={rc} stdout={out[-300:]!r} stderr={err[:300]!r}")
        chk("the Valheim install was located",
            re.search(r"Valheim install \.+ found", out) is not None,
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
        chk("default LD_PRELOAD contains doorstop only",
            env.get("LD_PRELOAD") == "libdoorstop_x64.so", env.get("LD_PRELOAD"))
        chk("default overlay game id is cleared", env.get("SteamOverlayGameId") == "", env.get("SteamOverlayGameId"))
        chk("default Vulkan overlay is disabled", env.get("DISABLE_VK_LAYER_VALVE_steam_overlay_1") == "1", env)
        chk("native launcher observes game exit", "Valheim has closed" in out, out[-500:])
        chk("LD_LIBRARY_PATH is the game's doorstop_libs",
            env.get("LD_LIBRARY_PATH") == str(Path(valheim_dir) / "doorstop_libs"),
            env.get("LD_LIBRARY_PATH"))
        chk("the game ran in its own directory", rec["cwd"] == str(valheim_dir),
            rec["cwd"])
        # argv is the game, -console, and from client 2.0.14 the Companion launch
        # payload. Pinned as an exact list rather than a set of "contains" checks,
        # because ORDER and COUNT both matter here: a duplicated argument or a payload
        # that arrived re-split on whitespace is exactly the kind of thing a loose
        # check waves through. This assertion was `== ["-console"]` and correctly
        # failed when the payload was added -- it is updated to the new reality, not
        # loosened.
        expected_argv = ["-console", "--phvalheim-launch",
                         T.launch_payload_b64(T.WORLD, port, vanilla=False)]
        chk("argv is the game, -console and the Companion launch payload",
            rec["argv"][1:] == expected_argv, rec["argv"])

        # Nothing flatpak-shaped may appear on a native run.
        chk("no flatpak-spawn wrapper leaked into the native launch",
            "flatpak" not in " ".join(rec["argv"]).lower(), rec["argv"])

        # An independently launched game has no PhValheim lock. The process
        # guard still must reject the click BEFORE requesting or syncing files.
        import time
        T.clear_logs()
        external = subprocess.Popen([str(Path(valheim_dir) / "valheim.x86_64")])
        try:
            started = T.wait_for_json(T.VALHEIM_LOG, timeout=10)
            before = len(T.FakeServer.requests)
            rc, blocked, err = run(exe, T.launch_url(T.WORLD, port, vanilla=False))
            chk("existing host game blocks another launch", started is not None and "Valheim is already running" in blocked, blocked[-500:])
            chk("existing game blocks sync requests", len(T.FakeServer.requests) == before, T.FakeServer.requests[before:])
            chk("existing game is not replaced", started is not None and T.wait_for_json(T.VALHEIM_LOG)["pid"] == started["pid"])
        finally:
            external.wait(timeout=10)

        # ---- overlay mutation controls ----
        #
        # The positive assertions above would also pass if the client put the overlay
        # path on LD_PRELOAD unconditionally. These prove the guard exists: with no
        # library on disk the client must NOT name it (ld.so would complain at every
        # launch and the game would start anyway -- the worst kind of warning), and the
        # opt-out must work without a release. Each control re-launches the same modded
        # world; the payload is already synced, so only the launch runs again.
        def modded_launch(label, extra_env=None):
            T.clear_logs()
            rc, out, err = run(exe, T.launch_url(T.WORLD, port, vanilla=False), extra_env)
            rec = T.wait_for_json(T.VALHEIM_LOG, timeout=90)
            chk(f"{label}: Valheim was executed on the host", rec is not None,
                f"rc={rc} stdout={out[-400:]!r} stderr={err[:400]!r}")
            return rec, out

        rec, out = modded_launch("explicit overlay opt-in", {"PHVALHEIM_ENABLE_OVERLAY": "1"})
        if rec:
            chk("opt-in restores renderer after doorstop", rec["env"].get("LD_PRELOAD") == f"libdoorstop_x64.so:{T.OVERLAY_SO}", rec["env"])
            chk("opt-in enables Vulkan overlay", rec["env"].get("ENABLE_VK_LAYER_VALVE_steam_overlay_1") == "1", rec["env"])
            chk("opt-in names Valheim", rec["env"].get("SteamOverlayGameId") == T.VALHEIM_APP_ID, rec["env"])

        print("\n-- control: no overlay library on disk --")
        T.OVERLAY_SO.unlink()
        try:
            rec, out = modded_launch("no library", {"PHVALHEIM_ENABLE_OVERLAY": "1"})
            if rec is not None:
                env = rec["env"]
                chk("no library: LD_PRELOAD is doorstop alone",
                    env.get("LD_PRELOAD") == "libdoorstop_x64.so", env.get("LD_PRELOAD"))
                chk("no library: no Steam app id is set",
                    not any(env.get(k) for k in ("SteamAppId", "SteamGameId", "SteamOverlayGameId")),
                    {k: env.get(k) for k in ("SteamAppId", "SteamGameId", "SteamOverlayGameId")})
            # Ui.Note wraps at 76 columns on word boundaries, and the path is a long
            # word, so the note arrives as two or three lines. Collapsing whitespace
            # puts it back together; the check is the sentence, not the layout.
            chk("no library: the client says why the overlay was skipped",
                f"Steam overlay skipped: {T.OVERLAY_SO} not found" in " ".join(out.split()),
                out[-600:])
        finally:
            T.OVERLAY_SO.write_bytes(b"")

        print("\n-- control: PHVALHEIM_NO_OVERLAY=1 --")
        rec, out = modded_launch("opt-out", {"PHVALHEIM_NO_OVERLAY": "1", "PHVALHEIM_ENABLE_OVERLAY": "1"})
        if rec is not None:
            env = rec["env"]
            chk("opt-out: LD_PRELOAD is doorstop alone",
                env.get("LD_PRELOAD") == "libdoorstop_x64.so", env.get("LD_PRELOAD"))
            chk("opt-out: no Steam app id is set",
                not any(env.get(k) for k in ("SteamAppId", "SteamGameId", "SteamOverlayGameId")),
                {k: env.get(k) for k in ("SteamAppId", "SteamGameId", "SteamOverlayGameId")})
        chk("opt-out: the client names the variable",
            "Steam overlay skipped: PHVALHEIM_NO_OVERLAY is set" in " ".join(out.split()),
            out[-600:])
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
