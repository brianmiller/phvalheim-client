#!/usr/bin/env python3
"""Exercise an exact shipped Windows client against isolated files with real attributes.

Requires native Windows CI, an unused Steam HKCU key, and an installed .NET 9 SDK.
No client build, Steam download, Valheim download, or actual game is involved.
The native Steam recording stub proves launch handoff only, not gameplay.

    python builders/test_windows_hidden.py --client installed/phvalheim-client.exe \
        --expected-sha SHA256 --evidence-dir evidence

Use --baseline with the original published 2.0.19 executable and its SHA256.
It must first seed successfully, then reproduce a required Hidden-only file denial.
"""

import argparse
import base64
from contextlib import contextmanager
import ctypes
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from urllib.parse import parse_qs, urlsplit
import uuid
import zipfile


HIDDEN, READONLY, NORMAL = 2, 1, 128
LIMIT = 1024 * 1024
STEAM_KEY = r"Software\Valve\Steam"
LOADER = {
    "winhttp.dll": b"fixture Windows loader v2\r\n",
    "doorstop_config.ini": b"[UnityDoorstop]\r\nenabled=true\r\n",
}
FOREIGN = ("libdoorstop_x64.so", "libdoorstop_x86.so", "libdoorstop.dylib")
POLICY = ".phvalheim-policy.json"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tail(path):
    if not path.is_file():
        return ""
    with path.open("rb") as source:
        source.seek(max(0, path.stat().st_size - LIMIT))
        return source.read(LIMIT).decode("utf-8", errors="replace")


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


class Attributes:
    def __init__(self):
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.kernel.GetFileAttributesW.argtypes = [ctypes.c_wchar_p]
        self.kernel.GetFileAttributesW.restype = ctypes.c_uint32
        self.kernel.SetFileAttributesW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32]
        self.kernel.SetFileAttributesW.restype = ctypes.c_int

    def get(self, path):
        value = self.kernel.GetFileAttributesW(str(path))
        if value == 0xFFFFFFFF:
            raise ctypes.WinError(ctypes.get_last_error())
        return value

    def set(self, path, value):
        if not self.kernel.SetFileAttributesW(str(path), value or NORMAL):
            raise ctypes.WinError(ctypes.get_last_error())

    def seed(self, path, content, flags):
        previous = self.get(path)
        self.set(path, previous & ~(HIDDEN | READONLY))
        try:
            path.write_bytes(content)
        finally:
            self.set(path, (previous & ~(NORMAL | HIDDEN | READONLY)) | flags)
        require(self.get(path) & (HIDDEN | READONLY) == flags,
                "Fixture attributes were not applied: " + str(path))

    def snapshot(self, paths):
        return {name: {"path": str(path), "attributes": self.get(path),
                       "hidden": bool(self.get(path) & HIDDEN),
                       "readonly": bool(self.get(path) & READONLY),
                       "sha256": sha256(path), "size": path.stat().st_size}
                for name, path in paths.items()}


def check_native_ci():
    require(sys.platform == "win32" and os.name == "nt", "Native Windows CI only; no Wine/WSL/Linux.")
    require(ctypes.sizeof(ctypes.c_void_p) == 8, "Use 64-bit Python for the win-x64 client.")
    require(not hasattr(ctypes.WinDLL("ntdll"), "wine_get_version"), "Wine is unsupported.")
    require(any(os.environ.get(name, "").lower() in ("true", "1")
                for name in ("CI", "GITHUB_ACTIONS", "TF_BUILD")),
            "Run in a disposable Windows CI account (CI=true), never a player account.")


def refuse_steam():
    import winreg

    for view in (winreg.KEY_WOW64_64KEY, winreg.KEY_WOW64_32KEY):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, STEAM_KEY, 0, winreg.KEY_READ | view):
                pass
        except FileNotFoundError:
            continue
        raise RuntimeError("Refusing existing HKCU\\" + STEAM_KEY + "; use a clean CI account.")


@contextmanager
def steam_registry(steam, executable):
    import winreg
    from ctypes import wintypes

    refuse_steam()
    advapi = ctypes.WinDLL("advapi32", use_last_error=True)
    create = advapi.RegCreateKeyExW
    create.argtypes = [wintypes.HKEY, wintypes.LPCWSTR, wintypes.DWORD,
                       wintypes.LPWSTR, wintypes.DWORD, wintypes.DWORD,
                       ctypes.c_void_p, ctypes.POINTER(wintypes.HKEY),
                       ctypes.POINTER(wintypes.DWORD)]
    create.restype = wintypes.LONG
    handle, disposition = wintypes.HKEY(), wintypes.DWORD()
    status = create(int(winreg.HKEY_CURRENT_USER), STEAM_KEY, 0, None, 0,
                    winreg.KEY_ALL_ACCESS | winreg.KEY_WOW64_64KEY, None,
                    ctypes.byref(handle), ctypes.byref(disposition))
    if status:
        raise ctypes.WinError(status)
    key = handle.value
    if disposition.value != 1:
        winreg.CloseKey(key)
        raise RuntimeError("Steam key appeared during setup; refusing to change it.")
    try:
        winreg.SetValueEx(key, "SteamPath", 0, winreg.REG_SZ, str(steam))
        winreg.SetValueEx(key, "SteamExe", 0, winreg.REG_SZ, str(executable))
        yield
    finally:
        # Delete only the key we created, never a pre-existing Steam configuration.
        try:
            require(winreg.QueryInfoKey(key)[0] == 0, "Unexpected Steam subkey; refusing recursive cleanup.")
            winreg.DeleteKeyEx(winreg.HKEY_CURRENT_USER, STEAM_KEY, winreg.KEY_WOW64_64KEY)
        finally:
            winreg.CloseKey(key)


def run_process(command, cwd, env, timeout, output):
    """Drain output continuously with a bounded tail, including on timeout."""
    buffer = bytearray()
    saw_error = False
    process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def drain():
        nonlocal saw_error
        previous = b""
        while True:
            block = process.stdout.read(8192)
            if not block:
                break
            saw_error |= b"ERROR" in previous + block
            previous = block[-4:]
            buffer.extend(block)
            if len(buffer) > LIMIT:
                del buffer[:-LIMIT]

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()
    timed_out = False
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        process.wait(timeout=10)
    finally:
        reader.join(timeout=5)
        if saw_error and b"ERROR" not in buffer:
            marker = b"[earlier output contained ERROR]\n"
            buffer[:] = marker + buffer[-(LIMIT - len(marker)):]
        output.write_bytes(bytes(buffer))
    require(not reader.is_alive(), "Output reader did not finish: " + output.name)
    process.stdout.close()
    require(not timed_out, f"Process timed out after {timeout}s; see {output}")
    return process.returncode, bytes(buffer).decode("utf-8", errors="replace")


def build_stub(root, env, evidence):
    dotnet = shutil.which("dotnet")
    require(dotnet is not None, "Installed .NET 9 SDK required; no SDK is downloaded.")
    project = root / "stub"
    project.mkdir()
    code, output = run_process([dotnet, "--list-sdks"], project, env, 20, evidence / "sdk.txt")
    versions = re.findall(r"^(9\.\d+\.\d+)\s", output, re.MULTILINE)
    require(code == 0 and versions, "Installed .NET SDK 9 was not found.")
    version = max(versions, key=lambda value: tuple(map(int, value.split("."))))
    save_json(project / "global.json", {"sdk": {"version": version, "rollForward": "disable"}})
    (project / "NuGet.Config").write_text(
        '<configuration><packageSources><clear /></packageSources></configuration>', encoding="utf-8")
    (project / "SteamStub.csproj").write_text('''<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType><TargetFramework>net9.0</TargetFramework>
    <UseAppHost>true</UseAppHost><AssemblyName>valheim</AssemblyName>
    <NuGetAudit>false</NuGetAudit>
  </PropertyGroup>
</Project>
''', encoding="utf-8")
    (project / "Program.cs").write_text('''using System;
using System.IO;
using System.Text.Json;
using System.Threading;
if (args.Length == 1 && args[0] == "--probe-appdata") {
    Console.WriteLine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));
    return;
}
var path = Environment.GetEnvironmentVariable("PHV_TEST_STEAM_LOG");
if (String.IsNullOrEmpty(path)) throw new Exception("Missing fixture recording path");
File.AppendAllText(path, JsonSerializer.Serialize(new {
    argv = args, cwd = Environment.CurrentDirectory, pid = Environment.ProcessId
}) + "\\n");
// Recording Steam/game-lifetime stub only; no actual Valheim is run.
// The valheim apphost lets Game.GetState observe a bounded lifetime, even on test failure.
Thread.Sleep(8000);
''', encoding="utf-8")
    code, _ = run_process([dotnet, "build", "SteamStub.csproj", "-c", "Release", "-o", "out",
                           "--nologo", "--verbosity", "quiet"], project, env, 90,
                          evidence / "stub-build.txt")
    executable = project / "out" / "valheim.exe"
    require(code == 0 and executable.is_file(), "Steam stub build failed; see stub-build.txt.")
    code, probe = run_process([str(executable), "--probe-appdata"], root, env, 20,
                             evidence / "appdata-probe.txt")
    known_folder = Path(probe.strip())
    require(code == 0 and known_folder.is_absolute() and known_folder.is_dir(),
            "Could not resolve the client's Windows diagnostic known folder.")
    return executable, known_folder


@contextmanager
def isolate_diagnostics(known_folder, appdata, root, env, evidence):
    target = appdata / "PhValheim"
    target.mkdir()
    link = known_folder / "PhValheim"
    if link == target:
        yield
        return
    # GetFolderPath(ApplicationData) may bypass APPDATA. A new junction redirects
    # only our log directory; an existing user directory (including a link) is refused.
    require(not os.path.lexists(link), "Refusing existing user data: " + str(link))
    command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", "mklink", "/J", str(link), str(target)]
    code, _ = run_process(command, root, env, 20, evidence / "diagnostic-junction.txt")
    require(code == 0, "Could not isolate Windows diagnostic logs; client was not run.")
    try:
        require(link.resolve() == target.resolve(), "Diagnostic junction points outside the fixture.")
        yield
    finally:
        require(link.resolve() == target.resolve(), "Diagnostic junction changed; refusing cleanup.")
        os.rmdir(link)


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, world, archive):
        self.world, self.archive = world, archive
        self.md5 = hashlib.md5(archive).hexdigest()
        self.requests = []
        super().__init__(("127.0.0.1", 0), FixtureHandler)


class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        request = urlsplit(self.path)
        query = parse_qs(request.query)
        self.server.requests.append(self.path)
        status, body = 200, b"fixture ready\n"
        if request.path == "/api.php":
            mode = query.get("mode", [""])[0]
            if mode:
                if query.get("world") != [self.server.world]:
                    status, body = 404, b"unknown world\n"
                elif mode == "getSyncState":
                    # Legacy checksum protocol avoids unrelated config-only downloads.
                    body = b""
                elif mode == "getMD5":
                    body = (self.server.md5 + "\n").encode()
                else:
                    status, body = 404, b"unsupported mode\n"
        elif request.path == f"/stateful/valheim/worlds/{self.server.world}/{self.server.world}.zip":
            body = self.server.archive
        else:
            status, body = 404, b"unknown route\n"
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Type", "application/zip" if request.path.endswith(".zip") else "text/plain")
        self.end_headers()
        self.wfile.write(body)


def policy(revision):
    # A world config policy, so every launch runs ConfigPolicy.Enforce (stage, edit, commit): the
    # writes a Hidden config file used to break. "managed" is the server's; "personal" the player's.
    return json.dumps({
        "version": 1, "minClientVersion": "2.0.17", "managedFiles": [],
        "files": [{"file": "fixture.cfg", "entries": [
            {"section": "Fixture", "key": "managed", "value": f"rev{revision}", "overridable": False},
            {"section": "Fixture", "key": "personal", "value": "default", "overridable": True}]}],
    }).encode()


def make_archive(revision=1):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in LOADER.items():
            archive.writestr(name, content)
        archive.writestr("BepInEx/core/BepInEx.Preloader.dll", b"fixture preloader, never executed\n")
        archive.writestr("BepInEx/config/fixture.cfg", f"[Fixture]\nmanaged = rev{revision}\npersonal = default\n".encode())
        archive.writestr("BepInEx/config/" + POLICY, policy(revision))
        # Original clients clone this directory. Keep it empty so baseline failure
        # identifies a required Hidden-only file, not a foreign ReadOnly file.
        archive.writestr("doorstop_libs/", b"")
    return buffer.getvalue()


def check_launch(record, payload, preloader):
    require(record.is_file(), "Steam recording stub was not invoked.")
    lines = record.read_text(encoding="utf-8").splitlines()
    require(len(lines) == 1, "Expected exactly one Steam launch request.")
    invocation = json.loads(lines[0])
    expected = ["-applaunch", "892970", "--doorstop-enabled", "true",
                "--doorstop-target-assembly", str(preloader), "-console",
                "--phvalheim-launch", payload]
    require(invocation["argv"] == expected, "Incorrect Steam launch arguments: " + repr(invocation["argv"]))


def exercise(args, root, evidence, attrs, env, executable):
    steam = root / "Steam"
    game = steam / "steamapps" / "common" / "Valheim"
    game.mkdir(parents=True)
    (game / "valheim.exe").write_bytes(b"fixture presence marker; never executed\n")
    (steam / "steamapps" / "appmanifest_892970.acf").write_text(
        '"AppState"\n{\n "appid" "892970"\n "installdir" "Valheim"\n}\n', encoding="utf-8")
    (steam / "steamapps" / "libraryfolders.vdf").write_text(
        '"libraryfolders"\n{\n "0"\n {\n  "path" "' + str(steam).replace("\\", "\\\\")
        + '"\n  "apps"\n  {\n   "892970" "1"\n  }\n }\n}\n', encoding="utf-8")
    world = "hidden_" + uuid.uuid4().hex
    server = FixtureServer(world, make_archive())
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"http://127.0.0.1:{server.server_port}"
    payload = base64.b64encode(f"launch?{world}??127.0.0.1?2456?127.0.0.1:{server.server_port}?http?0".encode()).decode()
    url = "phvalheim://?" + payload
    cache = Path(env["APPDATA"]) / "PhValheim" / "worlds" / "127.0.0.1" / world
    cached_world = cache / world
    backend = cached_world / "BepInEx" / "phvalheim.backend"
    preloader = cached_world / "BepInEx" / "core" / "BepInEx.Preloader.dll"
    targets = {name: game / name for name in LOADER}
    targets["backend"] = backend
    foreign = {name: game / "doorstop_libs" / name for name in FOREIGN}
    report = {"world": world, "origin": origin, "cases": {}}

    def run_case(label):
        print(f"Running {label} (timeout {args.timeout}s)...", flush=True)
        record = root / (label + "-steam.jsonl")
        child_env = dict(env, PHV_TEST_STEAM_LOG=str(record))
        before_requests = len(server.requests)
        result = report["cases"].setdefault(label, {})
        try:
            require(sha256(args.client) == args.expected_sha, "Client SHA256 changed before execution.")
            code, output = run_process([str(args.client), url], root, child_env, args.timeout,
                                       evidence / (label + "-stdout.txt"))
            result["exit_code"] = code
            require(code == 0, f"{label}: client exited {code}; see stdout evidence.")
            if record.exists():
                require("Valheim has closed. See you next time." in output,
                        f"{label}: client did not observe the game-lifetime stub exit.")
                require("could not observe the game through to its exit" not in output,
                        f"{label}: client failed to observe the game-lifetime stub.")
            return output, record
        finally:
            result["requests"] = server.requests[before_requests:]
            result["steam"] = tail(record)
            (evidence / (label + "-steam.jsonl")).write_text(tail(record), encoding="utf-8")
            log = Path(env["APPDATA"]) / "PhValheim" / "logs" / "phvalheim-client.log"
            (evidence / (label + "-client.log")).write_text(tail(log), encoding="utf-8")
            for index, fallback in enumerate(sorted((root / "temp").glob("PhValheim-*/logs/phvalheim-client.log"))[:4]):
                (evidence / f"{label}-fallback-{index}.log").write_text(tail(fallback), encoding="utf-8")
            save_json(evidence / "results.json", report)

    def correct_targets():
        for name, content in LOADER.items():
            require(targets[name].read_bytes() == content, "Wrong loader bytes: " + name)
        require(backend.read_bytes() == origin.encode(), "Backend URL was not rewritten correctly.")

    def denied(output, names):
        require("ERROR" in output, "Expected a client ERROR, not silent failure.")
        require(re.search(r"UnauthorizedAccessException|access.{0,30}denied|0x80070005", output, re.I),
                "Expected an actual Windows access denial, not setup/build/network failure.")
        require(any(name in output for name in names), "Denial did not identify the required target file.")
        require("mod loader" in output.lower(), "Failure did not reach loader installation.")

    try:
        with steam_registry(steam, executable):
            output, record = run_case("seed")
            require("ERROR" not in output, "Seed failed; this is not an expected baseline reproduction.")
            if args.baseline:
                require(re.search(r"PhValheim Client 2\.0\.19(?:\s|$)", output),
                        "Baseline must report published version 2.0.19.")
            correct_targets()
            check_launch(record, payload, preloader)
            archive = cache / (world + ".zip")
            require(archive.read_bytes() == server.archive, "Seed did not cache the served world archive.")
            require(any(path.endswith(".zip") for path in server.requests), "Seed never downloaded the world.")
            require(all(not attrs.get(path) & HIDDEN for path in targets.values()), "Seed unexpectedly has Hidden targets.")
            report["cases"]["seed"]["after"] = attrs.snapshot(targets)

            for name, path in targets.items():
                attrs.seed(path, ("old hidden sentinel: " + name).encode(), HIDDEN)
            for name, path in foreign.items():
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(("unused foreign sentinel: " + name).encode())
                attrs.set(path, (attrs.get(path) & ~NORMAL) | HIDDEN | READONLY)
            before = attrs.snapshot({**targets, **foreign})
            report["cases"]["hidden"] = {"before": before}
            save_json(evidence / "results.json", report)
            try:
                output, record = run_case("hidden")
            finally:
                report["cases"]["hidden"]["after"] = attrs.snapshot({**targets, **foreign})
                save_json(evidence / "results.json", report)
            after = report["cases"]["hidden"]["after"]
            require(not any(urlsplit(path).path.endswith(".zip")
                            for path in report["cases"]["hidden"]["requests"]),
                    "Hidden run must reuse the cached world, not download/extract a replacement.")
            require(archive.read_bytes() == server.archive, "Cached archive changed during the hidden case.")
            for name in foreign:
                require(after[name] == before[name], "Unrelated foreign file changed: " + name)
            if args.baseline:
                denied(output, LOADER)
                require(not record.exists(), "Baseline unexpectedly requested Steam.")
                for name in targets:
                    require(after[name] == before[name], "Baseline modified a denied target: " + name)
            else:
                require("ERROR" not in output, "Hidden replacement reported ERROR; see hidden-stdout.txt.")
                correct_targets()
                require(all(after[name]["hidden"] for name in targets), "Hidden was lost from a required target.")
                check_launch(record, payload, preloader)

            # Make the DLL the only required write blocker, including for baseline.
            attrs.seed(targets["doorstop_config.ini"], LOADER["doorstop_config.ini"], 0)
            attrs.seed(backend, origin.encode(), HIDDEN)
            dll = targets["winhttp.dll"]
            attrs.seed(dll, b"old readonly hidden DLL sentinel", HIDDEN | READONLY)
            before = attrs.snapshot({**targets, **foreign})
            report["cases"]["readonly"] = {"before": before}
            save_json(evidence / "results.json", report)
            try:
                try:
                    output, record = run_case("readonly")
                finally:
                    report["cases"]["readonly"]["after"] = attrs.snapshot({**targets, **foreign})
                    save_json(evidence / "results.json", report)
                after = report["cases"]["readonly"]["after"]
                denied(output, ["winhttp.dll"])
                require(not record.exists(), "ReadOnly failure still requested Steam.")
                require(after["winhttp.dll"] == before["winhttp.dll"], "ReadOnly DLL bytes/attributes changed.")
                for name in foreign:
                    require(after[name] == before[name], "ReadOnly case changed unrelated file: " + name)
            finally:
                attrs.set(dll, attrs.get(dll) & ~READONLY)

            if not args.baseline:
                every_file_hidden(args, attrs, report, evidence, run_case, server, cache, game, env,
                                  cached_world, targets, correct_targets, payload, preloader, check_launch)
            report["passed"] = True
    finally:
        save_json(evidence / "results.json", report)
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def every_file_hidden(args, attrs, report, evidence, run_case, server, cache, game, env,
                      cached_world, targets, correct_targets, payload, preloader, check_launch):
    """Issue #25 at its widest: every file the client made or will touch is Hidden (none ReadOnly).

    Two runs: a relaunch (config policy enforced on Hidden config files, the sync record, the logs)
    and a world update (download over a Hidden cached archive, install, settings, sync record).
    Both must launch with no ERROR, apply the server's settings, keep the player's, and preserve
    Hidden on stable managed files: personal config, sync record, and GameDir loader files.
    Ordinary relaunches must also preserve Hidden on the backend. Full world replacement
    regenerates the backend (absent from the archive) via PhValheimPrep after installation;
    its file identity must change and its attributes must match the fresh seed backend.
    The cached archive may be replaced, and the archive-authoritative manifest may take
    new attributes during installation, as may the newly generated backend.
    With --expect-config-denial (a build from before this fix) the relaunch must fail
    with an access denial while applying the world's settings: the test can fail.
    """
    config = cached_world / "BepInEx" / "config" / "fixture.cfg"
    manifest = cached_world / "BepInEx" / "config" / POLICY
    # Syncer uses PhValheimServerRoot / (WorldName + suffix); cache is that root.
    sync_record = cache / (cache.name + ".sync")
    archive = cache / (cache.name + ".zip")

    def hide_everything(label):
        hidden = []
        for base in (cache, game, Path(env["APPDATA"]) / "PhValheim" / "logs"):
            for directory, _, files in os.walk(base):
                for filename in files:
                    path = Path(directory) / filename
                    value = attrs.get(path)
                    if path.parent.name == "doorstop_libs" or value & READONLY:
                        continue  # the foreign ReadOnly fixtures stay as they are
                    attrs.set(path, (value & ~NORMAL) | HIDDEN)
                    hidden.append(str(path))
        require(str(config) in hidden and str(manifest) in hidden, "Config files were not part of the Hidden set.")
        require(str(sync_record) in hidden and str(archive) in hidden,
                "Sync record and cached archive were not part of the Hidden set.")
        report["cases"].setdefault(label, {})["hidden_before"] = len(hidden)
        return hidden

    def snapshot(hidden):
        result = {}
        for name in hidden:
            path = Path(name)
            entry = {"exists": None, "attributes": None, "hidden": None, "readonly": None,
                     "sha256": None, "size": None, "file_id": None}
            result[name] = entry
            try:
                stat = path.stat()
                entry.update(exists=True, size=stat.st_size, file_id=[stat.st_dev, stat.st_ino])
                value = attrs.get(path)
                entry.update(attributes=value, hidden=bool(value & HIDDEN), readonly=bool(value & READONLY))
                entry["sha256"] = sha256(path)
            except FileNotFoundError:
                entry["exists"] = False
            except OSError as error:
                entry["error"] = str(error)
        return result

    @contextmanager
    def hidden_case(label):
        hidden = hide_everything(label)
        result = report["cases"][label]
        result["before"] = snapshot(hidden)
        result["expected_world_md5"] = server.md5
        result["replacement_note"] = (
            "The cached archive may be replaced; archive and archive-authoritative manifest "
            "attributes are recorded without requiring preservation after replacement. "
            "Full world replacement also regenerates the backend, which is absent from the "
            "archive; PhValheimPrep creates it afterward with fresh seed attributes. "
            "Ordinary relaunches must preserve backend Hidden.")
        save_json(evidence / "results.json", report)
        try:
            require(not any("error" in entry for entry in result["before"].values()),
                    "Could not snapshot every Hidden file before " + label)
            yield
        finally:
            result["after"] = snapshot(hidden)
            result["changes"] = {}
            for name in hidden:
                before, after = result["before"][name], result["after"][name]
                fields = [key for key in before if before[key] != after.get(key)]
                if fields or "error" in after:
                    result["changes"][name] = {
                        "fields": fields,
                        "missing": after["exists"] is False,
                        "replaced": (before["file_id"] != after["file_id"]
                                     if before["file_id"] and after["file_id"] else None),
                    }
            save_json(evidence / "results.json", report)
            for path in (manifest, archive):
                before, after = result["before"][str(path)], result["after"][str(path)]
                print(f"{label}: {path}: attributes {before['attributes']} -> {after['attributes']}; "
                      f"SHA256 {before['sha256']} -> {after['sha256']}; "
                      f"change={result['changes'].get(str(path), {})}", flush=True)
        require(not any("error" in entry for entry in result["after"].values()),
                "Could not snapshot every Hidden file after " + label)

    def config_text():
        return config.read_text(encoding="utf-8")

    attrs.seed(config, b"[Fixture]\nmanaged = tampered\npersonal = mine\n", 0)
    with hidden_case("all-hidden"):
        output, record = run_case("all-hidden")
    if args.expect_config_denial:
        require("ERROR" in output, "A build without the fix should have failed on Hidden config files.")
        require(re.search(r"UnauthorizedAccessException|access.{0,30}denied|0x80070005", output, re.I),
                "Expected an access denial on a Hidden config file.")
        require("mod settings" in output, "The failure was not in applying the world's settings.")
        require(not record.exists(), "A failed settings pass must not launch the game.")
        report["cases"]["all-hidden"]["config_denied"] = True
        return
    require("ERROR" not in output, "Every-file-Hidden relaunch reported ERROR; see all-hidden-stdout.txt.")
    check_launch(record, payload, preloader)
    correct_targets()
    text = config_text()
    require("managed = rev1" in text, "The server's setting was not enforced on a Hidden config file.")
    require("personal = mine" in text, "The player's own setting was not kept.")
    for path in (config, manifest, sync_record, *targets.values()):
        require(attrs.get(path) & HIDDEN, "Hidden was lost from " + str(path))

    server.archive = make_archive(2)
    server.md5 = hashlib.md5(server.archive).hexdigest()
    with hidden_case("all-hidden-update"):
        output, record = run_case("all-hidden-update")
    require("ERROR" not in output, "Every-file-Hidden world update reported ERROR; see all-hidden-update-stdout.txt.")
    require(any(urlsplit(p).path.endswith(".zip") for p in report["cases"]["all-hidden-update"]["requests"]),
            "The world update did not download the new archive.")
    require(archive.read_bytes() == server.archive,
            "The Hidden cached archive was not replaced by the new one.")
    check_launch(record, payload, preloader)
    correct_targets()
    text = config_text()
    require("managed = rev2" in text, "The updated world's setting was not applied.")
    require("personal = mine" in text, "The player's own setting was lost in the update.")
    for path in (config, sync_record, *(targets[name] for name in LOADER)):
        require(attrs.get(path) & HIDDEN, "Hidden was lost from " + str(path))
    result = report["cases"]["all-hidden-update"]
    backend_before = result["before"][str(targets["backend"])]
    backend_after = result["after"][str(targets["backend"])]
    result["backend_regeneration_note"] = (
        "Full world replacement removes the old Hidden backend from the active world. "
        "The archive contains no backend; PhValheimPrep generates a new file after "
        "replacement, with a different file identity and the fresh seed backend's attributes.")
    require(backend_before["hidden"] is True, "Backend was not Hidden before full world replacement.")
    require(backend_before["file_id"] and backend_after["file_id"],
            "Backend file identities are required to verify regeneration.")
    require(backend_before["file_id"] != backend_after["file_id"],
            "Full world replacement did not regenerate the backend.")
    require(backend_after["attributes"] == report["cases"]["seed"]["after"]["backend"]["attributes"],
            "Regenerated backend attributes differ from the fresh seed backend.")
    sync_text = sync_record.read_text(encoding="utf-8")
    report["cases"]["all-hidden-update"]["sync_record_contents"] = sync_text
    require(sync_text.splitlines() == ["worldMd5=" + server.md5, "modsMd5=", "configMd5="],
            "The sync record does not describe the updated world's current MD5.")
    report["cases"]["all-hidden-update"]["passed"] = True

    original_attributes = attrs.get(config)
    try:
        attrs.set(config, (original_attributes & ~NORMAL) | HIDDEN | READONLY)
        before_bytes = config.read_bytes()
        result = report["cases"]["config-readonly-update"] = {
            "before": attrs.snapshot({"fixture.cfg": config}),
            "before_contents_base64": base64.b64encode(before_bytes).decode("ascii"),
        }
        require(result["before"]["fixture.cfg"]["attributes"] & (HIDDEN | READONLY) == HIDDEN | READONLY,
                "The personal config ReadOnly control was not applied.")
        server.archive = make_archive(3)
        server.md5 = hashlib.md5(server.archive).hexdigest()
        result["expected_world_md5"] = server.md5
        save_json(evidence / "results.json", report)
        try:
            output, record = run_case("config-readonly-update")
        finally:
            try:
                result["after"] = attrs.snapshot({"fixture.cfg": config})
                result["after_contents_base64"] = base64.b64encode(config.read_bytes()).decode("ascii")
            finally:
                save_json(evidence / "results.json", report)
        require("ERROR" in output, "ReadOnly personal config update did not report ERROR.")
        require(re.search(r"mod settings|fixture\.cfg|ConfigPolicy|BepInEx[\\/]config",
                          output[output.index("ERROR"):], re.I),
                "ReadOnly personal config failure did not identify the settings/config stage.")
        require(not record.exists(), "ReadOnly personal config failure still requested Steam.")
        require(any(urlsplit(p).path.endswith(".zip") for p in result["requests"]),
                "ReadOnly personal config control did not download the world update.")
        require(config.read_bytes() == before_bytes,
                "ReadOnly personal config bytes changed during the failed update.")
        require(result["after"] == result["before"],
                "ReadOnly personal config bytes/attributes changed during the failed update.")
        text = config_text()
        require("managed = rev2" in text, "The failed update changed the cached world's setting.")
        require("personal = mine" in text, "The failed update lost the player's own setting.")
        result["passed"] = True
        save_json(evidence / "results.json", report)
    finally:
        attrs.set(config, (attrs.get(config) & ~READONLY) | (original_attributes & READONLY))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--expected-sha", required=True, help="SHA256 of the exact extracted/installed EXE")
    parser.add_argument("--baseline", action="store_true", help="Require original 2.0.19 Hidden denial")
    parser.add_argument("--expect-config-denial", action="store_true",
                        help="A build from before the every-file fix: require the Hidden config pass to be denied")
    parser.add_argument("--evidence-dir", type=Path)
    parser.add_argument("--timeout", type=int, default=175, help="Client timeout in seconds (default 175)")
    args = parser.parse_args()
    evidence = None
    try:
        check_native_ci()
        args.client = args.client.resolve(strict=True)
        require(args.client.suffix.lower() == ".exe" and args.client.is_file(), "--client must be the actual Windows EXE.")
        args.expected_sha = args.expected_sha.lower()
        require(re.fullmatch(r"[0-9a-f]{64}", args.expected_sha), "--expected-sha must be a SHA256 digest.")
        require(sha256(args.client) == args.expected_sha, "Client SHA256 mismatch; refusing to execute.")
        require(1 <= args.timeout <= 180, "--timeout must be between 1 and 180 seconds.")
        refuse_steam()
        evidence = (args.evidence_dir.resolve() if args.evidence_dir
                    else Path(tempfile.mkdtemp(prefix="phv-hidden-evidence-")))
        if args.evidence_dir:
            evidence.mkdir(parents=True, exist_ok=False)
        print("Evidence: " + str(evidence), flush=True)
        save_json(evidence / "candidate.json", {"client": str(args.client), "sha256": args.expected_sha,
                                               "baseline": args.baseline, "gameplay_tested": False})
        attrs = Attributes()
        with tempfile.TemporaryDirectory(prefix="phv-hidden-") as temporary:
            root = Path(temporary)
            env = dict(os.environ)
            for name in tuple(env):
                if name.upper().startswith(("PHVALHEIM_", "PHV_TEST_", "DOTNET_", "CORECLR_", "COR_")):
                    del env[name]
            # Keep the registered USERPROFILE so the probe and client can resolve
            # ApplicationData; isolate_diagnostics redirects its PhValheim directory.
            for name, directory in (("APPDATA", "roaming"), ("LOCALAPPDATA", "local"),
                                    ("TEMP", "temp"), ("TMP", "temp")):
                path = root / directory
                path.mkdir(exist_ok=True)
                env[name] = str(path)
            env.update(DOTNET_CLI_HOME=str(root), DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1",
                       DOTNET_CLI_TELEMETRY_OPTOUT="1", DOTNET_NOLOGO="1", PHVALHEIM_VERBOSE="1",
                       DOTNET_BUNDLE_EXTRACT_BASE_DIR=str(root / "bundles"),
                       NUGET_PACKAGES=str(root / "packages"), NUGET_HTTP_CACHE_PATH=str(root / "nuget-cache"))
            try:
                executable, known_folder = build_stub(root, env, evidence)
                with isolate_diagnostics(known_folder, Path(env["APPDATA"]), root, env, evidence):
                    exercise(args, root, evidence, attrs, env, executable)
            finally:
                # Windows will not remove ReadOnly fixtures during TemporaryDirectory cleanup.
                for directory, _, files in os.walk(root):
                    for filename in files:
                        path = Path(directory) / filename
                        attrs.set(path, attrs.get(path) & ~(HIDDEN | READONLY))
        print("PASS: " + ("published baseline denied Hidden writes" if args.baseline
                          else "older build denied on Hidden config files, as expected" if args.expect_config_denial
                          else "Hidden loader/backend replacements, every-file-Hidden relaunch and update, and Steam handoff")
              + "; ReadOnly control passed. No real game was run.")
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        message = str(error)
        if evidence is not None and evidence.is_dir():
            (evidence / "failure.txt").write_text(message[:LIMIT] + "\n", encoding="utf-8")
        print("FAIL: " + message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
