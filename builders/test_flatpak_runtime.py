#!/usr/bin/env python3
"""End-to-end tests for the PhValheim Flatpak.

verify_flatpak.sh asserts what is IN the bundle. This asserts what it DOES,
which for this package is nearly the whole point: a Flatpak that installs
perfectly and never opens a phvalheim:// link is a total failure of the
feature, and every table in the bundle would still look correct.

The three things that can only be tested by running it:

  1. The URL handler. The bundle is installed for real, and a phvalheim://
     link is opened three ways -- by the registered-URI machinery (gio), and
     by an actual mouse click on an actual link in an actual browser. The
     browser click is the one that matches what a user does.

  2. The sandbox escape. Every useful thing the client does happens on the
     host: finding Steam, reading the Valheim install, starting the game. A
     stub Steam and a stub Valheim sit on the host and record exactly what
     they were handed, so "did the escape work" has a yes/no answer rather
     than an inference.

  3. Environment hygiene across that escape. The stub Valheim dumps its whole
     environment, so what the game is handed is observed rather than assumed.

     Measured, because it is easy to get backwards: a host command does NOT
     inherit the sandbox's environment. It inherits the environment of the
     host's flatpak session helper -- the user's real session -- plus
     whatever the client passes explicitly with --env. So DISPLAY and the
     user's own XDG settings arrive correctly on their own, and the client
     adds only the doorstop variables.

     That mechanism is asserted directly, not just its consequences: if
     flatpak ever starts forwarding the caller environment, our per-app
     XDG_CONFIG_HOME would reach the game and a player's characters and
     worlds would be written inside our app directory, to be deleted on
     uninstall.

Both the vanilla and modded launch paths are covered. The modded path needs a
PhValheim server, so there is a small fake one here serving the three
endpoints Syncer actually calls.

NOT COVERED: a real Steam, a real Valheim, a real GPU. The stubs prove the
client hands the host the right command in the right directory with the right
environment; they cannot prove Valheim then starts. And nothing here runs on
SteamOS or Bazzite -- this is a Debian container.

usage: test_flatpak_runtime.py <bundle.flatpak> <expected-version>
"""

import base64
import hashlib
import http.server
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import zipfile
from pathlib import Path

APP_ID = "com.phvalheim.Client"
DESKTOP = APP_ID + ".desktop"
HOME = Path(os.environ.get("HOME", "/root"))
# The fake Steam library deliberately does NOT live in /tmp.
#
# Flatpak gives every app a PRIVATE /tmp, so a library placed there is
# invisible to the client and ValheimGetter reports "Valheim not found" --
# which looks exactly like a product bug and is not one.
#
# /run/media is the Steam Deck's SD-card and external-drive path and is
# granted by the manifest, so putting the library here tests
# --filesystem=/run/media at the same time: a Deck user with Valheim on the
# SD card is the case most likely to break.
FAKE = Path("/run/media/phv-testdrive")
STEAM_LOG = FAKE / "steam.log"
VALHEIM_LOG = FAKE / "valheim.json"
SHOTS = Path("/git/builders/.flatpak_shots")

# Which installation the innie used. flatpak refuses every modifying --user
# operation when running as root, so a container build uses --system. Only the
# location differs; export and URL registration are the same either way.
SCOPE = os.environ.get("FLATPAK_SCOPE", "--user")
FLATPAK_EXPORTS = Path(os.environ.get(
    "FLATPAK_EXPORTS_DIR",
    str(HOME / ".local/share/flatpak/exports/share")))

WORLD = "Valhalla"
SRV_HOST = "127.0.0.1"

checks = 0
fails = 0
notes = []


def ok(msg):
    global checks
    checks += 1
    print(f"  PASS  {msg}", flush=True)


def bad(msg, expected, actual):
    global checks, fails
    checks += 1
    fails += 1
    print(f"  FAIL  {msg}\n        expected: {expected}\n        actual:   {actual}", flush=True)


def eq(msg, expected, actual):
    if actual == expected:
        ok(msg)
    else:
        bad(msg, expected, actual if actual not in (None, "") else "<empty>")


def contains(msg, needle, haystack):
    if haystack and needle in haystack:
        ok(msg)
    else:
        bad(msg, f"something containing {needle!r}", (haystack or "<empty>")[:300])


def absent(msg, needle, haystack):
    if not haystack or needle not in haystack:
        ok(msg)
    else:
        bad(msg, f"no {needle!r}", haystack[:300])


def sh(cmd, timeout=180, env=None, check=False):
    """Run on the test host (which is the container)."""
    e = dict(os.environ)
    if env:
        e.update(env)
    p = subprocess.run(cmd, shell=isinstance(cmd, str), env=e, timeout=timeout,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       stdin=subprocess.DEVNULL)
    out = p.stdout.decode(errors="replace")
    if check and p.returncode != 0:
        print(out[-2000:])
        raise RuntimeError(f"command failed ({p.returncode}): {cmd}")
    return p.returncode, out


def session_env():
    """The environment a desktop session would have, so that xdg-open, gio and
    the browser can all find the Flatpak's exported desktop file."""
    return {
        "DISPLAY": ":99",
        "XDG_DATA_HOME": str(HOME / ".local/share"),
        "XDG_DATA_DIRS": f"{FLATPAK_EXPORTS}:/usr/local/share:/usr/share",
        "XDG_CONFIG_HOME": str(HOME / ".config"),
        "XDG_RUNTIME_DIR": "/run/user/0",
    }


# --------------------------------------------------------------------------
# The fake host: a stub Steam and a stub Valheim that record what they get.
# --------------------------------------------------------------------------

# These are substituted with str.replace, NOT %-formatting. The shell stub
# contains its own printf '%s', which %-formatting silently consumes -- the
# stub then logged the substitution dict instead of Steam's arguments, and the
# assertions failed against a log full of PosixPath repr.
STEAM_STUB = """#!/bin/sh
# Stub Steam. Records its arguments and exits. Never starts anything.
{
  printf 'ARGV'
  for a in "$@"; do printf '\\t%s' "$a"; done
  printf '\\n'
} >> __LOG__
exit 0
"""

VALHEIM_STUB = """#!/usr/bin/python3
# Stub Valheim. Records argv, cwd and the COMPLETE environment it was handed.
# The environment is the interesting part: it is the only way to see what
# survived the trip out of the Flatpak sandbox.
import json, os, sys
with open("__LOG__", "w") as f:
    json.dump({"argv": sys.argv, "cwd": os.getcwd(), "env": dict(os.environ)}, f, indent=1)
"""


def build_fake_host():
    if FAKE.exists():
        shutil.rmtree(FAKE)
    FAKE.mkdir(parents=True)

    steam = Path("/usr/local/bin/steam")
    steam.write_text(STEAM_STUB.replace("__LOG__", str(STEAM_LOG)))
    steam.chmod(0o755)

    lib = FAKE / "steamlib"
    (lib / "steamapps" / "common" / "Valheim").mkdir(parents=True)
    (lib / "steamapps" / "appmanifest_892970.acf").write_text(
        '"AppState"\n{\n\t"appid"\t\t"892970"\n\t"name"\t\t"Valheim"\n}\n')

    valheim = lib / "steamapps" / "common" / "Valheim" / "valheim.x86_64"
    valheim.write_text(VALHEIM_STUB.replace("__LOG__", str(VALHEIM_LOG)))
    valheim.chmod(0o755)
    (lib / "steamapps" / "common" / "Valheim" / "valheim_Data").mkdir(exist_ok=True)

    # Platform.cs hardcodes ~/.steam/steam as the Steam root on Linux, and
    # Steam.cs reads steamapps/libraryfolders.vdf from there.
    steamroot = HOME / ".steam" / "steam" / "steamapps"
    steamroot.mkdir(parents=True, exist_ok=True)
    (steamroot / "libraryfolders.vdf").write_text(
        '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' % lib)

    return lib / "steamapps" / "common" / "Valheim"


def build_world_zip(path):
    """What Syncer expects to unpack: doorstop payload plus a BepInEx tree."""
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("doorstop_config.ini", "[General]\nenabled=true\n")
        z.writestr("doorstop_libs/libdoorstop_x64.so", "not-really-a-library\n")
        z.writestr("BepInEx/core/BepInEx.Preloader.dll", "not-really-an-assembly\n")
        z.writestr("BepInEx/plugins/PhValheimCompanion.dll", "stub\n")


class FakeServer(http.server.BaseHTTPRequestHandler):
    zip_bytes = b""
    page = b""

    def log_message(self, *a):
        pass

    def _send(self, body, ctype="text/plain"):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # Syncer calls exactly three things.
        if self.path.startswith("/api.php?mode=getMD5"):
            self._send(b"0123456789abcdef0123456789abcdef\n")
        elif self.path.startswith("/api.php"):
            self._send(b"ok\n")
        elif self.path.endswith(".zip"):
            self._send(self.zip_bytes, "application/zip")
        elif self.path.startswith("/link"):
            self._send(self.page, "text/html")
        else:
            self.send_error(404)


def start_fake_server(zip_path, link_url):
    FakeServer.zip_bytes = Path(zip_path).read_bytes()
    FakeServer.page = ("""<!doctype html><meta charset=utf-8>
<title>PhValheim launch link</title>
<style>html,body{margin:0;height:100%%;background:#1b1b1b}
a{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;
  font:700 40px sans-serif;color:#fff;text-decoration:none;background:#2d6a2d}</style>
<a id="go" href="%s">JOIN WORLD</a>""" % link_url).encode()

    sock = socket.socket()
    sock.bind((SRV_HOST, 0))
    port = sock.getsockname()[1]
    sock.close()

    srv = http.server.ThreadingHTTPServer((SRV_HOST, port), FakeServer)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, port


def screenshot(name, env):
    """Best-effort screenshot for diagnosing a failed browser test.

    ImageMagick 7 (Debian trixie) dropped the bare `import` command in favour
    of `magick import`, and xwd is the fallback if neither is present. This is
    diagnostic output, so it must never fail the run.
    """
    SHOTS.mkdir(parents=True, exist_ok=True)
    target = SHOTS / name
    for cmd in (f"magick import -window root {target}",
                f"import -window root {target}",
                f"xwd -root -silent | magick xwd:- {target}"):
        rc, _ = sh(cmd, env=env, timeout=60)
        if rc == 0 and target.exists():
            return str(target)
    return "<screenshot unavailable>"


def launch_url(world, port, vanilla):
    """Build the phvalheim:// URL exactly as the server's web UI does:
    launch?world?password?host?port?phvalheimHost?scheme?vanilla"""
    payload = "?".join([
        "launch", world, "swordfish", SRV_HOST, "2456",
        f"{SRV_HOST}:{port}", "http", "1" if vanilla else "0",
    ])
    return "phvalheim://?" + base64.b64encode(payload.encode()).decode()


def wait_for_text(path, needle, timeout=180):
    """Wait for a specific string to appear in a file.

    Waiting for the file to merely EXIST is not good enough for the Steam
    stub. The client writes to it twice: once to start Steam, then -- ten
    seconds later, after the sleep that gives Steam time to come up -- again
    with -applaunch. Returning on first existence would assert against a log
    that does not contain the launch line yet.
    """
    path = Path(path)
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if needle in path.read_text():
                return True
        except OSError:
            pass
        time.sleep(0.5)
    return False


def wait_for_json(path, timeout=180):
    """Wait for a file to contain complete, parseable JSON, so a read that
    lands mid-write is retried rather than reported as a malformed result."""
    path = Path(path)
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            time.sleep(0.5)
    return None


def clear_logs():
    for p in (STEAM_LOG, VALHEIM_LOG):
        if p.exists():
            p.unlink()
    world_state = HOME / ".config" / "PhValheim"
    if world_state.exists():
        shutil.rmtree(world_state)


# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------

def scenario_install(bundle, version):
    print("\n-- installing the bundle --")
    sh(f"flatpak uninstall {SCOPE} --noninteractive {APP_ID} 2>/dev/null || true")

    rc, out = sh(f"flatpak install {SCOPE} --noninteractive --bundle {bundle}", timeout=600)
    if rc == 0:
        ok("bundle installs")
    else:
        bad("bundle installs", "exit 0", out[-600:])
        return False

    rc, out = sh(f"flatpak list {SCOPE} --app --columns=application,version")
    contains("app is listed after install", APP_ID, out)
    contains(f"listed version is {version}", version, out)
    return True


def scenario_exports():
    print("\n-- desktop integration and URL-scheme registration --")

    exported = FLATPAK_EXPORTS / "applications" / DESKTOP
    if exported.exists():
        ok("flatpak exported the desktop file into the user's share")
    else:
        bad("flatpak exported the desktop file into the user's share",
            str(exported), "missing")
        return

    text = exported.read_text()
    # flatpak rewrites Exec= on export. This is the line the desktop actually
    # runs when a phvalheim:// link is opened, so it is worth reading rather
    # than assuming.
    m = re.search(r"^Exec=(.*)$", text, re.M)
    execline = m.group(1) if m else ""
    contains("exported Exec runs the app through flatpak", "flatpak run", execline)
    contains("exported Exec passes the URL through", "%u", execline)
    contains("exported desktop keeps the scheme handler",
             "x-scheme-handler/phvalheim", text)

    sh(f"update-desktop-database {FLATPAK_EXPORTS / 'applications'}")

    env = session_env()
    rc, out = sh("gio mime x-scheme-handler/phvalheim", env=env)
    contains("gio reports our app as the handler for phvalheim://", DESKTOP, out)

    rc, out = sh("xdg-mime query default x-scheme-handler/phvalheim", env=env)
    contains("xdg-mime resolves the scheme to our desktop file", DESKTOP, out)


def scenario_runs_at_all(version):
    print("\n-- the app starts inside the runtime --")
    # A self-contained .NET binary on org.freedesktop.Platform is not a given:
    # it needs a compatible glibc and ICU. If this fails, nothing else can work.
    rc, out = sh(f"flatpak run {APP_ID}", timeout=120)
    contains("runs with no arguments and prints usage", "Usage:", out)
    contains("reports its version", "PhValheim Client Version", out)

    m = re.search(r"PhValheim Client Version ([0-9][^\s]*)", out)
    eq("reported version matches the csproj", version, m.group(1) if m else "<not found>")
    absent("no unhandled .NET exception on startup", "Unhandled exception", out)

    rc, out = sh(f"flatpak run {APP_ID} 'phvalheim://?not-base64!!'", timeout=120)
    contains("rejects a malformed URL cleanly", "malformed phvalheim URL", out)
    absent("malformed URL does not throw", "Unhandled exception", out)


def scenario_host_escape():
    print("\n-- the sandbox escape itself --")
    # Before trusting any launch result, prove flatpak-spawn --host works at
    # all. If --talk-name=org.freedesktop.Flatpak were missing, every launch
    # test below would fail for this one reason, and the failure would look
    # like a launcher bug.
    rc, out = sh(
        f"flatpak run --command=flatpak-spawn {APP_ID} --host /bin/sh -c "
        f"'echo ESCAPED:$(hostname)'", timeout=120)
    contains("flatpak-spawn --host reaches the host", "ESCAPED:", out)

    # And prove the sandbox is real, so the check above is not vacuous: the
    # host has our stub steam on PATH, the sandbox must not.
    rc, out = sh(f"flatpak run --command=sh {APP_ID} -c 'command -v steam || echo NOSTEAM'",
                 timeout=120)
    contains("the sandbox genuinely cannot see the host's steam", "NOSTEAM", out)

    rc, out = sh(f"flatpak run --command=flatpak-spawn {APP_ID} --host "
                 f"/bin/sh -c 'command -v steam'", timeout=120)
    contains("but the host can", "/usr/local/bin/steam", out)

    # The assumption the whole environment design rests on: a host command
    # inherits the user's real session, NOT our sandbox. If flatpak ever
    # changes that, the client must start scrubbing XDG_CONFIG_HOME and
    # friends again -- so assert the mechanism directly rather than only
    # asserting its consequences.
    #
    # FLATPAK_ID is set in every sandbox and nowhere else, which makes it the
    # cleanest probe available.
    rc, out = sh(f"flatpak run --command=flatpak-spawn {APP_ID} --host "
                 f"/bin/sh -c 'echo SANDBOX_ENV=[$FLATPAK_ID]'", timeout=120)
    contains("host commands do not inherit our sandbox environment",
             "SANDBOX_ENV=[]", out)


def open_with_gio(url):
    """Hand the URL to the desktop's registered handler and DO NOT WAIT.

    The desktop entry is Terminal=true, so gio launches a terminal emulator
    and blocks until it exits -- and the client deliberately sits for ten
    seconds so a user can read the output. Waiting on gio would just be
    waiting on the client. The oracle is the stub's log file, not gio's exit.
    """
    clear_logs()
    env = {**os.environ, **session_env()}
    return subprocess.Popen(["gio", "open", url], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            stdin=subprocess.DEVNULL)


def scenario_vanilla_launch(port):
    print("\n-- vanilla world, opened through the registered URI (gio) --")
    url = launch_url(WORLD, port, vanilla=True)
    opener = open_with_gio(url)

    # -applaunch is the line that matters; see wait_for_text.
    got = wait_for_text(STEAM_LOG, "-applaunch", timeout=240)
    opener.terminate()
    if not got:
        seen = STEAM_LOG.read_text() if STEAM_LOG.exists() else "<stub never invoked>"
        bad("opening a vanilla phvalheim:// link reaches Steam on the host",
            "the stub Steam invoked with -applaunch", f"within 240s, saw: {seen!r}")
        return
    ok("opening a vanilla phvalheim:// link reaches Steam on the host")

    log = STEAM_LOG.read_text()
    contains("Steam was asked to launch Valheim's app id", "892970", log)
    contains("Steam was passed -applaunch", "-applaunch", log)
    contains("Steam was given the world's connect address",
             f"{SRV_HOST}:2456", log)
    absent("no stray '--' leaked into Steam's arguments as a real argument",
           "ARGV\t--\t", log)


def assert_valheim_env(rec, valheim_dir):
    env = rec["env"]

    print("     environment that survived the escape:")
    eq("DOORSTOP_ENABLED is set", "1", env.get("DOORSTOP_ENABLED"))
    contains("DOORSTOP_TARGET_ASSEMBLY points at the synced BepInEx preloader",
             "BepInEx/core/BepInEx.Preloader.dll", env.get("DOORSTOP_TARGET_ASSEMBLY", ""))
    contains("DOORSTOP_TARGET_ASSEMBLY is under the world directory",
             f"PhValheim/worlds/{SRV_HOST}/{WORLD}", env.get("DOORSTOP_TARGET_ASSEMBLY", ""))
    contains("LD_PRELOAD injects doorstop", "libdoorstop_x64.so", env.get("LD_PRELOAD", ""))
    eq("LD_LIBRARY_PATH is the game's doorstop_libs",
       str(Path(valheim_dir) / "doorstop_libs"), env.get("LD_LIBRARY_PATH"))

    # Nothing of OURS may leak into the game.
    #
    # These assert the property, not an implementation: the client does not
    # set these variables at all, because a host command inherits the user's
    # real session rather than our sandbox (proved outright by the
    # "sandbox environment does not reach host commands" check above). If
    # flatpak ever starts forwarding the caller environment, these are what
    # catch it -- Valheim keeps characters and worlds under XDG_CONFIG_HOME,
    # so our per-app copy reaching the game would put a player's saves inside
    # our app directory, to be deleted on uninstall.
    absent("XDG_CONFIG_HOME does not point inside ~/.var/app",
           ".var/app", env.get("XDG_CONFIG_HOME", ""))
    absent("XDG_DATA_HOME does not point inside ~/.var/app",
           ".var/app", env.get("XDG_DATA_HOME", ""))
    absent("PATH has no /app entries from our runtime", "/app/", env.get("PATH", ""))
    absent("XDG_DATA_DIRS has no /app entries", "/app/", env.get("XDG_DATA_DIRS", ""))
    absent("the game is not told it is running inside our Flatpak",
           APP_ID, env.get("FLATPAK_ID", ""))

    # Valheim needs somewhere to draw. It does not come from us: a host
    # command inherits the environment of the host's flatpak session helper,
    # i.e. the user's real session. This asserts the game actually ends up
    # with a display, whatever route it took.
    contains("the game has a DISPLAY to open a window on", ":", env.get("DISPLAY", ""))


def scenario_modded_launch(port, valheim_dir):
    print("\n-- modded world, opened by CLICKING A LINK IN A BROWSER --")
    url = launch_url(WORLD, port, vanilla=False)
    clear_logs()

    env = session_env()
    profile = "/tmp/chromeprofile"
    shutil.rmtree(profile, ignore_errors=True)

    browser = subprocess.Popen(
        ["chromium", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage",
         "--no-first-run", "--no-default-browser-check", "--disable-extensions",
         "--window-size=1280,800", "--window-position=0,0",
         f"--user-data-dir={profile}",
         f"http://{SRV_HOST}:{port}/link.html"],
        env={**os.environ, **env},
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        time.sleep(8)  # page load
        screenshot("browser-before-click.png", env)

        # A REAL click, not location.href. Chromium treats an external
        # protocol navigation without a user gesture differently -- it can
        # block it outright -- so a scripted navigation would be testing
        # something a user never does.
        sh("xdotool mousemove 640 400 click 1", env=env, timeout=30)

        rec = wait_for_json(VALHEIM_LOG, timeout=240)
        screenshot("browser-after-click.png", env)
    finally:
        browser.terminate()
        try:
            browser.wait(timeout=20)
        except subprocess.TimeoutExpired:
            browser.kill()

    if rec is None:
        bad("clicking a phvalheim:// link in a browser launches the game",
            "the stub Valheim to be executed on the host",
            f"no execution within 240s (screenshots in {SHOTS})")
        return
    ok("clicking a phvalheim:// link in a browser launches the game")

    # Sync actually happened, on the way through.
    world_root = HOME / ".config" / "PhValheim" / "worlds" / SRV_HOST / WORLD / WORLD
    if (world_root / "BepInEx" / "core" / "BepInEx.Preloader.dll").exists():
        ok("the world's mod payload was downloaded and extracted")
    else:
        bad("the world's mod payload was downloaded and extracted",
            str(world_root / "BepInEx"), "missing")

    if (world_root / "BepInEx" / "phvalheim.backend").exists():
        ok("the companion backend file was written")
    else:
        bad("the companion backend file was written",
            str(world_root / "BepInEx" / "phvalheim.backend"), "missing")

    if (Path(valheim_dir) / "doorstop_config.ini").exists():
        ok("doorstop was installed into the Valheim directory on the host")
    else:
        bad("doorstop was installed into the Valheim directory on the host",
            str(Path(valheim_dir) / "doorstop_config.ini"), "missing")

    # The launch itself.
    argv = rec["argv"]
    contains("Valheim was started with -console", "-console", " ".join(argv))
    absent("no literal '--' reached Valheim's argv", "--", " ".join(argv[1:]))
    eq("Valheim was started in its own directory (flatpak-spawn --directory)",
       str(valheim_dir), rec["cwd"])

    assert_valheim_env(rec, valheim_dir)


def scenario_uninstall():
    print("\n-- uninstall --")
    rc, out = sh(f"flatpak uninstall {SCOPE} --noninteractive {APP_ID}", timeout=300)
    if rc == 0:
        ok("uninstalls cleanly")
    else:
        bad("uninstalls cleanly", "exit 0", out[-400:])

    exported = FLATPAK_EXPORTS / "applications" / DESKTOP
    if not exported.exists():
        ok("the exported desktop file is removed")
    else:
        bad("the exported desktop file is removed", "no file", str(exported))

    sh(f"update-desktop-database {FLATPAK_EXPORTS / 'applications'} 2>/dev/null || true")
    rc, out = sh("gio mime x-scheme-handler/phvalheim", env=session_env())
    absent("phvalheim:// is no longer handled by us", DESKTOP, out)


# --------------------------------------------------------------------------

def start_display():
    subprocess.Popen(["Xvfb", ":99", "-screen", "0", "1280x800x24", "-nolisten", "tcp"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    Path("/run/user/0").mkdir(parents=True, exist_ok=True)
    os.chmod("/run/user/0", 0o700)
    for _ in range(40):
        rc, _ = sh("xdpyinfo -display :99 >/dev/null 2>&1", timeout=20)
        if rc == 0:
            return True
        time.sleep(0.5)
    return False


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    bundle, version = sys.argv[1], sys.argv[2]

    print(f"Flatpak runtime tests: {os.path.basename(bundle)} (expecting {version})")
    print("=" * 72)

    if not start_display():
        print("  FAIL  could not start Xvfb; the browser test cannot run")
        return 1

    valheim_dir = build_fake_host()
    zip_path = FAKE / f"{WORLD}.zip"
    build_world_zip(zip_path)
    srv, port = start_fake_server(zip_path, launch_url(WORLD, 0, vanilla=False))

    # The link on the page has to carry the real port, which is only known
    # after the socket is bound.
    FakeServer.page = FakeServer.page.replace(
        launch_url(WORLD, 0, vanilla=False).encode(),
        launch_url(WORLD, port, vanilla=False).encode())

    def run(fn, *a):
        """One scenario blowing up must not take the rest of the run with it.
        An exception is a failure of that scenario, not a reason to stop
        reporting on the others."""
        try:
            fn(*a)
        except Exception as e:  # noqa: BLE001 - a crash IS the finding here
            bad(f"scenario {fn.__name__} completed without crashing",
                "no exception", f"{type(e).__name__}: {e}")

    try:
        if not scenario_install(bundle, version):
            return 1
        run(scenario_exports)
        run(scenario_runs_at_all, version)
        run(scenario_host_escape)
        run(scenario_vanilla_launch, port)
        run(scenario_modded_launch, port, valheim_dir)
        run(scenario_uninstall)
    finally:
        srv.shutdown()

    print("\n" + "-" * 72)
    print("COVERAGE NOTES")
    print("  Stubs, not the real thing: Steam and Valheim here are scripts that")
    print("  record what they were given. These tests prove the client hands the")
    print("  host the right command, directory and environment. They cannot prove")
    print("  Valheim then starts, and nothing here has run on SteamOS or Bazzite.")
    print("  A Flatpak Steam is detected and refused, not supported.")
    for n in notes:
        print(f"  {n}")
    print("=" * 72)

    if fails == 0:
        print(f"OK: {checks} flatpak runtime checks passed")
        return 0
    print(f"FAILED: {fails} of {checks} flatpak runtime checks failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
