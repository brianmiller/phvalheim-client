#!/usr/bin/env python3
"""Behavioural test battery for the PhValheim Client .msi.

verify_msi.sh asserts what is IN the package. This asserts what the package
DOES when installed, which is a different question and the one that kept
being answered wrong.

Every scenario here exists because a real bug shipped past a fully green
verify_msi.sh run on 2026-09-11:

  fresh      files landed but were never checked against the File table
  upgrade    2.0.12 -> 2.0.13 left ONLY the .ico; the exe was deleted and
             never reinstalled. No gate could see it: the wine check is a
             fresh install.
  uninstall  never tested at all
  repair     never tested at all
  wizard     four of the six bugs were RENDERING faults -- a maroon stock
             bitmap, blue body text, three missing paragraphs, the wrong
             typeface. All of them passed every table assertion. The only
             thing that ever caught them was Brian looking at the screen,
             so this runs the wizard on a virtual display, screenshots each
             page and asserts on the pixels.

Usage:
    test_install_matrix.py <msi> <version> [--prev <older.msi>] [--shots <dir>]
                           [--only <scenario,...>]

Exit status is the gate: 0 only if every scenario passed.
"""

import os
import re
import subprocess
import sys
import time

# XDG_RUNTIME_DIR is not set in this container. Install and uninstall do not
# care, but `msiexec /fa` (repair) exits 69 with "XDG_RUNTIME_DIR is invalid or
# not set" -- a wine environment complaint that looks exactly like a package
# defect if you read only the exit code.
XDG_DIR = "/tmp/xdg-runtime"
os.makedirs(XDG_DIR, mode=0o700, exist_ok=True)
os.chmod(XDG_DIR, 0o700)
WINE_ENV = {"WINEDEBUG": "-all", "WINEDLLOVERRIDES": "mscoree=d",
            "XDG_RUNTIME_DIR": XDG_DIR}
INSTALL_SUBPATH = "PhValheim/phvalheim-client"
EXPECT_CMD = r'"%appdata%\PhValheim\phvalheim-client\phvalheim-client.exe" "%1"'

checks = 0
fails = 0


def ok(msg):
    global checks
    checks += 1
    print(f"  PASS  {msg}", flush=True)


def bad(msg, expected, actual):
    global checks, fails
    checks += 1
    fails += 1
    print(f"  FAIL  {msg}\n        expected: {expected}\n        actual:   {actual}", flush=True)


def expect(msg, want, got):
    ok(msg) if want == got else bad(msg, want, got)


def run(cmd, env=None, timeout=600, check=False):
    e = dict(os.environ)
    e.update(WINE_ENV)
    if env:
        e.update(env)
    p = subprocess.run(cmd, shell=isinstance(cmd, str), env=e, timeout=timeout,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if check and p.returncode != 0:
        raise RuntimeError(f"{cmd} -> {p.returncode}\n{p.stdout.decode(errors='replace')[-2000:]}")
    return p.returncode, p.stdout.decode(errors="replace")


# --------------------------------------------------------------------------
# wine prefix helpers
# --------------------------------------------------------------------------

def new_prefix(tag):
    """A fresh prefix per scenario. Sharing one is how an earlier attempt at
    this had two scenarios silently clobber each other's results."""
    prefix = f"/tmp/wp-{tag}"
    run(f"rm -rf {prefix}")
    run("wineboot -i", env={"WINEPREFIX": prefix}, timeout=600)
    run("wineserver -w", env={"WINEPREFIX": prefix}, timeout=300)
    return prefix


def msiexec(prefix, args, timeout=900, display=None):
    env = {"WINEPREFIX": prefix}
    if display:
        env["DISPLAY"] = display
    rc, out = run(f"wine msiexec {args}", env=env, timeout=timeout)
    run("wineserver -w", env=env, timeout=300)
    return rc, out


def installed_files(prefix):
    """name -> size for everything under the install directory."""
    found = {}
    for root, _dirs, names in os.walk(os.path.join(prefix, "drive_c", "users")):
        if INSTALL_SUBPATH.replace("/", os.sep) not in root.replace("\\", os.sep):
            continue
        for n in names:
            found[n] = os.path.getsize(os.path.join(root, n))
    return found


def read_registry(prefix):
    """Concatenated wine registry text. REG_EXPAND_SZ shows as str(2):"...",
    which is the distinction that makes the URL handler work at all."""
    text = ""
    for f in ("system.reg", "user.reg"):
        p = os.path.join(prefix, f)
        if os.path.exists(p):
            with open(p, encoding="utf-8", errors="replace") as fh:
                text += fh.read()
    return text


def reg_block(text, key):
    """The lines of one [Key] block. Pass the key with SINGLE backslashes;
    wine's .reg files double them, and hand-escaping that at each call site
    is how the first version of this check reported every key absent."""
    doubled = key.replace("\\", "\\\\")
    m = re.search(r"^\[" + re.escape(doubled) + r"\][^\n]*\n(.*?)(?=^\[|\Z)",
                  text, re.S | re.M)
    return m.group(1) if m else None


def arp_entries(text):
    """Uninstall entries whose DisplayName mentions PhValheim -> version."""
    out = {}
    for m in re.finditer(
            r"^\[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\([^\]]+)\][^\n]*\n(.*?)(?=^\[|\Z)",
            text, re.S | re.M):
        code, body = m.group(1), m.group(2)
        if "PhValheim" in body:
            v = re.search(r'"DisplayVersion"="([^"]*)"', body)
            out[code.replace("\\\\", "\\")] = v.group(1) if v else "?"
    return out


# --------------------------------------------------------------------------
# scenarios
# --------------------------------------------------------------------------

def assert_installed_state(prefix, want_sizes, label):
    files = installed_files(prefix)
    for name, size in want_sizes.items():
        if name not in files:
            bad(f"{label}: {name} is installed", "present", "MISSING")
        else:
            expect(f"{label}: {name} installed at the right size", size, files[name])
    extra = set(files) - set(want_sizes)
    if extra:
        bad(f"{label}: no unexpected files in the install dir", "only the payload", sorted(extra))
    else:
        ok(f"{label}: no unexpected files in the install dir")

    reg = read_registry(prefix)
    blk = reg_block(reg, r"Software\Classes\phvalheim")
    if blk is None:
        bad(f"{label}: HKCR\\phvalheim exists", "key present", "absent")
    else:
        ok(f"{label}: HKCR\\phvalheim exists")
        if '"URL Protocol"' in blk:
            ok(f"{label}: 'URL Protocol' marker written")
        else:
            bad(f"{label}: 'URL Protocol' marker written", "value present", blk.strip()[:80])
        if "PhValheim Client" in blk:
            ok(f"{label}: default value names the product")
        else:
            bad(f"{label}: default value names the product", "PhValheim Client", blk.strip()[:80])

    cmd = reg_block(reg, r"Software\Classes\phvalheim\shell\open\command")
    if cmd is None:
        bad(f"{label}: the phvalheim:// command is registered", "key present", "absent")
    else:
        # str(2) is REG_EXPAND_SZ. As plain REG_SZ Windows hands the literal
        # %appdata%\... to CreateProcess and the handler silently never runs.
        if "str(2):" in cmd:
            ok(f"{label}: command is REG_EXPAND_SZ")
        else:
            bad(f"{label}: command is REG_EXPAND_SZ", 'str(2):"..."', cmd.strip()[:100])
        want = EXPECT_CMD.replace("\\", "\\\\").replace('"', '\\"')
        if want in cmd:
            ok(f"{label}: command line points at the installed exe")
        else:
            bad(f"{label}: command line points at the installed exe", want, cmd.strip()[:160])


def scenario_fresh(msi, version, sizes):
    print("\n-- fresh install --", flush=True)
    p = new_prefix("fresh")
    rc, _ = msiexec(p, f'/i "{winepath(msi)}" /qn')
    expect("fresh: msiexec exit code", 0, rc)
    assert_installed_state(p, sizes, "fresh")
    entries = arp_entries(read_registry(p))
    expect("fresh: exactly one Add/Remove Programs entry", 1, len(entries))
    if entries:
        expect("fresh: ARP reports the right version", version, list(entries.values())[0])
    return p


def scenario_uninstall(msi, sizes):
    print("\n-- uninstall leaves nothing behind --", flush=True)
    p = new_prefix("uninst")
    msiexec(p, f'/i "{winepath(msi)}" /qn')
    if not installed_files(p):
        bad("uninstall: fixture installed first", "files present", "install failed, scenario void")
        return
    rc, _ = msiexec(p, f'/x "{winepath(msi)}" /qn')
    expect("uninstall: msiexec exit code", 0, rc)
    left = installed_files(p)
    expect("uninstall: payload removed", {}, left)
    reg = read_registry(p)
    if reg_block(reg, r"Software\Classes\phvalheim\shell\open\command") is None:
        ok("uninstall: phvalheim:// handler removed")
    else:
        bad("uninstall: phvalheim:// handler removed", "key gone", "still registered")
    expect("uninstall: ARP entry removed", 0, len(arp_entries(reg)))


MINIMAL_WXS = """<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="RepairControl" Language="1033" Version="1.0.0"
           Manufacturer="Control" UpgradeCode="6F1B8E2A-0C4D-4E6F-9A1B-2C3D4E5F6071">
    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    <Media Id="1" Cabinet="c.cab" EmbedCab="yes" />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="AppDataFolder">
        <Directory Id="CtlDir" Name="RepairControl">
          <Component Id="Ctl" Guid="8A2C6D1E-3F5B-4A7C-8D9E-0F1A2B3C4D5E">
            <File Id="ctlFile" Name="control.txt" Source="control.txt" KeyPath="yes" />
          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="Main" Level="1" Title="Control">
      <ComponentRef Id="Ctl" />
    </Feature>
  </Product>
</Wix>
"""


def wine_can_repair():
    """Control: can wine repair ANY package here?

    Without this, a failing repair reads as a defect in our .msi. It is the
    same discipline as asserting a fixture reached its state -- if the control
    cannot be repaired either, the finding is about wine, not the package.
    """
    d = "/tmp/repair-control"
    run(f"rm -rf {d} && mkdir -p {d}")
    with open(f"{d}/minimal.wxs", "w") as fh:
        fh.write(MINIMAL_WXS)
    with open(f"{d}/control.txt", "w") as fh:
        fh.write("control payload\n")
    rc, out = run(f"cd {d} && wixl -a x64 -o control.msi minimal.wxs")
    if rc != 0 or not os.path.exists(f"{d}/control.msi"):
        return None, "control package would not build"
    p = new_prefix("repairctl")
    msiexec(p, f'/i "{winepath(d + "/control.msi")}" /qn')
    hit = [os.path.join(r, n)
           for r, _dd, ns in os.walk(os.path.join(p, "drive_c", "users"))
           for n in ns if n == "control.txt"]
    if not hit:
        return None, "control package did not install"
    os.remove(hit[0])
    code = product_code(f"{d}/control.msi")
    rc, _ = msiexec(p, f"/fa {code} /qn")
    restored = os.path.exists(hit[0])
    return (rc == 0 and restored), f"control repair rc={msi_error(rc)} restored={restored}"


def scenario_repair(msi, sizes):
    print("\n-- repair restores a deleted payload --", flush=True)
    p = new_prefix("repair")
    msiexec(p, f'/i "{winepath(msi)}" /qn')
    files = installed_files(p)
    if "phvalheim-client.exe" not in files:
        bad("repair: fixture installed first", "exe present", "install failed, scenario void")
        return
    for root, _d, names in os.walk(os.path.join(p, "drive_c", "users")):
        if "phvalheim-client.exe" in names and INSTALL_SUBPATH.replace("/", os.sep) in root:
            os.remove(os.path.join(root, "phvalheim-client.exe"))
    if "phvalheim-client.exe" in installed_files(p):
        bad("repair: fixture deleted the exe", "exe gone", "still present, scenario void")
        return
    # Repair takes the PRODUCT CODE, not a package path: wine's msiexec
    # answers a path with 1605 ERROR_UNKNOWN_PRODUCT, which arrives at the
    # shell as 69 and reads like an unrelated failure.
    code = product_code(msi)
    if not code:
        bad("repair: ProductCode readable", "a GUID", "not found in Property table")
        return
    rc, out = msiexec(p, f'/fa {code} /qn')
    restored = "phvalheim-client.exe" in installed_files(p)
    if rc == 0 and restored:
        expect("repair: msiexec exit code", "0", "0")
        assert_installed_state(p, sizes, "repair")
        return

    can, why = wine_can_repair()
    if can:
        # wine CAN repair, so this is ours.
        tail = " | ".join(l.strip() for l in out.strip().splitlines()[-6:] if l.strip())
        if tail:
            print(f"        msiexec said: {tail}", flush=True)
        bad("repair: restores a deleted payload", "exe restored, rc=0",
            f"rc={msi_error(rc)} restored={restored} (control repaired fine, so this is the package)")
    else:
        # Not a pass and not a fail -- an unrun check, said out loud.
        print(f"  SKIP  repair: wine cannot repair any package in this image "
              f"({why}); our package repaired rc={msi_error(rc)} restored={restored}", flush=True)
        print("        Repair is therefore UNVERIFIED here. Test it by hand on Windows.", flush=True)


def scenario_upgrade(msi, prev_msi, version, sizes):
    """THE scenario with no coverage before now. 2.0.13 deleted the exe on
    upgrade and installed nothing in its place."""
    print("\n-- upgrade over a previous version --", flush=True)
    p = new_prefix("upgrade")
    msiexec(p, f'/i "{winepath(prev_msi)}" /qn')
    before = installed_files(p)
    if "phvalheim-client.exe" not in before:
        bad("upgrade: predecessor installed first", "exe present",
            "predecessor did not install, scenario void")
        return
    ok(f"upgrade: predecessor installed ({len(before)} files)")

    rc, _ = msiexec(p, f'/i "{winepath(msi)}" /qn')
    expect("upgrade: msiexec exit code", 0, rc)
    assert_installed_state(p, sizes, "upgrade")

    entries = arp_entries(read_registry(p))
    # Two entries means the upgrade installed SIDE BY SIDE instead of
    # replacing -- the failure mode a changed UpgradeCode produces.
    expect("upgrade: exactly one Add/Remove Programs entry (not side by side)",
           1, len(entries))
    if entries:
        expect("upgrade: ARP reports the new version", version, list(entries.values())[0])


# --------------------------------------------------------------------------
# wizard rendering
# --------------------------------------------------------------------------

def scenario_wizard(msi, shots_dir):
    """Run the wizard in FULL UI on a virtual display and assert on pixels.

    /qn skips InstallUISequence entirely, so the quiet install below can pass
    against a package that cannot draw a single window -- which is exactly
    what shipped.
    """
    print("\n-- wizard renders (full UI on Xvfb) --", flush=True)
    os.makedirs(shots_dir, exist_ok=True)
    display = ":99"
    xvfb = subprocess.Popen(["Xvfb", display, "-screen", "0", "1024x768x24"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(2)
        p = new_prefix("wizard")
        env = dict(os.environ)
        env.update(WINE_ENV)
        env.update({"WINEPREFIX": p, "DISPLAY": display})
        proc = subprocess.Popen(f'wine msiexec /i "{winepath(msi)}"', shell=True, env=env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        win = None
        for _ in range(90):
            time.sleep(2)
            rc, out = run(f"DISPLAY={display} xdotool search --name 'PhValheim Client'")
            ids = [l for l in out.split() if l.strip().isdigit()]
            if ids:
                win = ids[-1]
                break
        if not win:
            bad("wizard: a window appears at all", "PhValheim Client window",
                "no window after 180s -- the package may have no UI")
            proc.kill()
            return
        ok("wizard: the Welcome window appears")

        shot = os.path.join(shots_dir, "01-welcome.png")
        run(f"DISPLAY={display} import -window {win} '{shot}'", timeout=120)
        assert_wizard_pixels(shot, "welcome")

        # Advance to Confirm, so a broken Next is caught too.
        run(f"DISPLAY={display} xdotool windowactivate --sync {win} key --window {win} Return", timeout=60)
        time.sleep(4)
        shot2 = os.path.join(shots_dir, "02-confirm.png")
        run(f"DISPLAY={display} import -window {win} '{shot2}'", timeout=120)
        if os.path.exists(shot2) and os.path.getsize(shot2) > 0:
            ok("wizard: Next advances to a second page (screenshot captured)")
        else:
            bad("wizard: Next advances to a second page", "screenshot", "capture failed")

        proc.kill()
        print(f"        screenshots in {shots_dir}", flush=True)
    finally:
        xvfb.terminate()


def assert_wizard_pixels(path, label):
    """The oracles for the four rendering bugs that shipped."""
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        bad(f"wizard/{label}: screenshot captured", "a png", "capture produced nothing")
        return
    try:
        from PIL import Image
    except ImportError:
        bad(f"wizard/{label}: pixel analysis available", "python3-pil", "PIL not installed")
        return

    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    maroon = blue = dark = 0
    dark_rows = set()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if abs(r - 128) < 40 and g < 60 and b < 60:
                maroon += 1
            elif b > r + 40 and b > g + 40 and b > 90:
                blue += 1
            elif r < 110 and g < 110 and b < 110:
                dark += 1
                dark_rows.add(y)

    total = w * h
    # The one pixel assertion PROVEN to fail: building with WixUI_Minimal
    # instead of our dialog set reports 32616 px (18.4%), which is exactly the
    # maroon pixel count in the stock WixUI_Bmp_Dialog. Ours is a white banner.
    if maroon < total * 0.02:
        ok(f"wizard/{label}: no maroon stock bitmap ({maroon} px)")
    else:
        bad(f"wizard/{label}: no maroon stock bitmap", "<2% of the window",
            f"{maroon} px ({100.0*maroon/total:.1f}%) -- stock WiX dialogs?")

    # RENDER FLOOR, not a style check. On Windows an unstyled string renders
    # blue and stops at its first newline; wine does NOT reproduce that -- a
    # build with every {\Style} prefix stripped still renders dark here, so
    # this check CANNOT fail for that cause. Proven, not assumed. What it does
    # catch is a window that drew no text at all. The style prefixes are
    # guarded by verify_msi.sh, which asserts them in the Control table.
    if dark > blue and dark > 500:
        ok(f"wizard/{label}: the page drew dark text ({dark} dark vs {blue} blue)")
    else:
        bad(f"wizard/{label}: the page drew dark text", ">500 dark px, more dark than blue",
            f"{dark} dark vs {blue} blue -- blank or garbled render")

    # Also a floor. Truncation caused by a missing style prefix is a Windows
    # rendering behaviour that wine does not reproduce, so this cannot fail for
    # that cause either. It would catch a page that rendered nearly empty.
    if label == "welcome":
        if len(dark_rows) >= 40:
            ok(f"wizard/{label}: the page is not near-empty ({len(dark_rows)} text rows)")
        else:
            bad(f"wizard/{label}: the page is not near-empty", ">=40 rows with text",
                f"{len(dark_rows)} rows")


def msi_error(rc):
    """Shell exit codes are truncated mod 256, so MSI's 1605 arrives as 69 and
    looks like nothing at all. Recover the likely original."""
    known = {0: "ok", 1602: "user cancelled", 1603: "fatal error during install",
             1605: "ERROR_UNKNOWN_PRODUCT", 1618: "another install in progress",
             1619: "package could not be opened", 1620: "package could not be opened",
             1638: "another version already installed"}
    for full, name in known.items():
        if full % 256 == rc % 256 and full != 0:
            return f"{rc} (= {full} {name})"
    return str(rc)


def product_code(msi):
    _rc, out = run(f"msiinfo export '{msi}' Property")
    for line in out.replace("\r", "").split("\n"):
        f = line.split("\t")
        if len(f) == 2 and f[0] == "ProductCode":
            return f[1]
    return None


def winepath(p):
    return "Z:" + os.path.abspath(p).replace("/", "\\")


# --------------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    msi, version = args[0], args[1]
    prev = shots = None
    only = None
    i = 2
    while i < len(args):
        if args[i] == "--prev":
            prev = args[i + 1]; i += 2
        elif args[i] == "--shots":
            shots = args[i + 1]; i += 2
        elif args[i] == "--only":
            only = set(args[i + 1].split(",")); i += 2
        else:
            i += 1
    shots = shots or "/tmp/wizard-shots"

    rc, out = run(f"msiinfo export '{msi}' File")
    sizes = {}
    for line in out.replace("\r", "").split("\n")[3:]:
        f = line.split("\t")
        if len(f) > 3:
            sizes[f[2].split("|")[-1]] = int(f[3])
    if not sizes:
        print("  FAIL  could not read the File table; nothing to assert against")
        return 1
    print(f"Install matrix for {os.path.basename(msi)} ({version})")
    print("=" * 64)
    print(f"payload: {sizes}")

    def want(name):
        return only is None or name in only

    if want("fresh"):
        scenario_fresh(msi, version, sizes)
    if want("uninstall"):
        scenario_uninstall(msi, sizes)
    if want("repair"):
        scenario_repair(msi, sizes)
    if want("upgrade"):
        if prev:
            scenario_upgrade(msi, prev, version, sizes)
        else:
            print("\n-- upgrade --\n  SKIP  no --prev package given", flush=True)
    if want("wizard"):
        scenario_wizard(msi, shots)

    print("\n" + "-" * 64)
    print("COVERAGE NOTES -- what this battery does NOT prove:")
    print("  * The upgrade scenario uses a predecessor built from THIS source, whose")
    print("    exe carries no Win32 version resource. It therefore cannot reproduce")
    print("    the 2.0.12 case (a Windows-built, VERSIONED exe on disk) that made")
    print("    2.0.13 delete the exe on upgrade. Verified: the broken build PASSES")
    print("    this scenario. That bug is guarded by verify_msi.sh's File.Version")
    print("    assertion instead. Real 2.0.12 cannot be installed under wine at all.")
    print("  * Wine does not reproduce Windows' rendering of UNSTYLED strings (blue,")
    print("    truncated at the first newline). A build with every style prefix")
    print("    stripped renders correctly here, so the pixel checks are a render")
    print("    FLOOR, not a style check. The maroon-bitmap check is a real oracle.")
    print("  * Repair is skipped: wine cannot repair any package in this image.")
    print("  * Look at the screenshots. Four of the six bugs that shipped were")
    print("    visible and nothing automated caught them.")
    print("=" * 64)
    if fails == 0:
        print(f"OK: {checks} behavioural checks passed")
        return 0
    print(f"FAILED: {fails} of {checks} behavioural checks failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
