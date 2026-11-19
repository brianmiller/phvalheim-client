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
    key = winreg.HKEYType(handle.value)
    if disposition.value != 1:
        key.Close()
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
            key.Close()


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
    <UseAppHost>true</UseAppHost><AssemblyName>SteamStub</AssemblyName>
    <NuGetAudit>false</NuGetAudit>
  </PropertyGroup>
</Project>
''', encoding="utf-8")
    (project / "Program.cs").write_text('''using System;
using System.IO;
using System.Text.Json;
if (args.Length == 1 && args[0] == "--probe-appdata") {
    Console.WriteLine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));
    return;
}
var path = Environment.GetEnvironmentVariable("PHV_TEST_STEAM_LOG");
if (String.IsNullOrEmpty(path)) throw new Exception("Missing fixture recording path");
File.AppendAllText(path, JsonSerializer.Serialize(new {
    argv = args, cwd = Environment.CurrentDirectory, pid = Environment.ProcessId
}) + "\\n");
''', encoding="utf-8")
    code, _ = run_process([dotnet, "build", "SteamStub.csproj", "-c", "Release", "-o", "out",
                           "--nologo", "--verbosity", "quiet"], project, env, 90,
                          evidence / "stub-build.txt")
    executable = project / "out" / "SteamStub.exe"
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


def make_archive():
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in LOADER.items():
            archive.writestr(name, content)
        archive.writestr("BepInEx/core/BepInEx.Preloader.dll", b"fixture preloader, never executed\n")
        archive.writestr("BepInEx/config/fixture.cfg", b"fixture=true\n")
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
            report["passed"] = True
    finally:
        save_json(evidence / "results.json", report)
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--expected-sha", required=True, help="SHA256 of the exact extracted/installed EXE")
    parser.add_argument("--baseline", action="store_true", help="Require original 2.0.19 Hidden denial")
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
            for name, directory in (("APPDATA", "roaming"), ("LOCALAPPDATA", "local"),
                                    ("USERPROFILE", "profile"), ("TEMP", "temp"), ("TMP", "temp")):
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
                          else "Hidden loader/backend replacements and Steam handoff")
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
