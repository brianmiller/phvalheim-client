#!/usr/bin/env python3
"""Compare extracted PUBLISHED 2.0.18 and current PUBLISHED 2.0.19 on native Windows CI.

Both clients use one disposable world, origin, Steam registry entry and filesystem.
Every run restores bytes, raw attributes, owner and DACL from the same case snapshot;
timestamps and file IDs are evidence only. The original 2.0.18 seed is retained.
Requires the existing harness's clean-account guards and installed .NET 9 SDK.
No MSI installation, client build, real Steam or gameplay is performed here.
Caller must establish published-MSI provenance; supplied EXE SHA256s are enforced.

    python builders/test_windows_hidden_pair.py --old-client extracted218.exe \
        --old-sha SHA256 --new-client extracted219.exe --new-sha SHA256 \
        --evidence-dir new-evidence-directory
"""

import argparse
import base64
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
from urllib.parse import urlsplit
import uuid

import test_windows_hidden as T


class Security:
    """Owner and DACL only: no SACL privilege or changes to user-account ACLs."""

    def __init__(self):
        self.api = ctypes.WinDLL("advapi32", use_last_error=True)
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        pointer = ctypes.c_void_p
        dword = ctypes.c_uint32
        self.api.GetFileSecurityW.argtypes = [ctypes.c_wchar_p, dword, pointer, dword,
                                              ctypes.POINTER(dword)]
        self.api.GetFileSecurityW.restype = ctypes.c_int
        self.api.ConvertSecurityDescriptorToStringSecurityDescriptorW.argtypes = [
            pointer, dword, dword, ctypes.POINTER(pointer), ctypes.POINTER(dword)]
        self.api.ConvertSecurityDescriptorToStringSecurityDescriptorW.restype = ctypes.c_int
        self.api.ConvertStringSecurityDescriptorToSecurityDescriptorW.argtypes = [
            ctypes.c_wchar_p, dword, ctypes.POINTER(pointer), ctypes.POINTER(dword)]
        self.api.ConvertStringSecurityDescriptorToSecurityDescriptorW.restype = ctypes.c_int
        self.api.GetSecurityDescriptorControl.argtypes = [pointer, ctypes.POINTER(ctypes.c_ushort),
                                                          ctypes.POINTER(dword)]
        self.api.GetSecurityDescriptorControl.restype = ctypes.c_int
        self.api.SetFileSecurityW.argtypes = [ctypes.c_wchar_p, dword, pointer]
        self.api.SetFileSecurityW.restype = ctypes.c_int
        self.kernel.LocalFree.argtypes = [pointer]
        self.kernel.LocalFree.restype = pointer

    def get(self, path):
        size = ctypes.c_uint32()
        self.api.GetFileSecurityW(str(path), 5, None, 0, ctypes.byref(size))
        if not size.value:
            raise ctypes.WinError(ctypes.get_last_error())
        descriptor = ctypes.create_string_buffer(size.value)
        if not self.api.GetFileSecurityW(str(path), 5, descriptor, size, ctypes.byref(size)):
            raise ctypes.WinError(ctypes.get_last_error())
        text = ctypes.c_void_p()
        if not self.api.ConvertSecurityDescriptorToStringSecurityDescriptorW(
                descriptor, 1, 5, ctypes.byref(text), None):
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            return ctypes.wstring_at(text)
        finally:
            self.kernel.LocalFree(text)

    def restore(self, path, sddl):
        current = self.get(path)
        if current == sddl:
            return
        descriptor = ctypes.c_void_p()
        if not self.api.ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl, 1, ctypes.byref(descriptor), None):
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            control, revision = ctypes.c_ushort(), ctypes.c_uint32()
            if not self.api.GetSecurityDescriptorControl(descriptor, ctypes.byref(control),
                                                         ctypes.byref(revision)):
                raise ctypes.WinError(ctypes.get_last_error())
            flags = 4 | (0x80000000 if control.value & 0x1000 else 0x20000000)
            if current.split("D:", 1)[0] != sddl.split("D:", 1)[0]:
                flags |= 1
            if not self.api.SetFileSecurityW(str(path), flags, descriptor):
                raise ctypes.WinError(ctypes.get_last_error())
        finally:
            self.kernel.LocalFree(descriptor)


def comparable(snapshot):
    return {name: {key: value for key, value in entry.items()
                   if key not in ("file_id", "mtime_ns")}
            for name, entry in snapshot.items()}


class FixtureFiles:
    def __init__(self, root, bases, attrs):
        self.root, self.bases, self.attrs = root, bases, attrs
        self.security = Security()

    def paths(self):
        yield self.root
        for base in self.bases:
            if base.exists():
                yield base
                for directory, dirs, files in os.walk(base, followlinks=False):
                    for name in sorted(dirs + files):
                        path = Path(directory) / name
                        T.require(not self.attrs.get(path) & 0x400,
                                  "Unexpected reparse point in disposable fixture: " + str(path))
                        yield path

    def snapshot(self):
        result = {}
        for path in self.paths():
            stat = path.stat()
            entry = {"kind": "directory" if path.is_dir() else "file",
                     "attributes": self.attrs.get(path), "owner_dacl_sddl": self.security.get(path),
                     "file_id": [stat.st_dev, stat.st_ino], "mtime_ns": stat.st_mtime_ns}
            if path.is_file():
                content = path.read_bytes()
                entry.update(bytes_base64=base64.b64encode(content).decode("ascii"),
                             sha256=hashlib.sha256(content).hexdigest(), size=len(content))
            result[path.relative_to(self.root).as_posix()] = entry
        return result

    def restore(self, snapshot):
        existing = list(self.paths())
        for path in existing:
            self.attrs.set(path, self.attrs.get(path) & ~(T.HIDDEN | T.READONLY))
        for path in sorted(existing, key=lambda p: len(p.parts), reverse=True):
            name = path.relative_to(self.root).as_posix()
            expected = snapshot.get(name)
            if expected is None or (expected["kind"] == "directory") != path.is_dir():
                if path.is_dir():
                    path.rmdir()
                else:
                    path.unlink()
        for name, entry in sorted(snapshot.items(), key=lambda item: len(Path(item[0]).parts)):
            path = self.root / name
            if entry["kind"] == "directory":
                path.mkdir(exist_ok=True)
            else:
                path.write_bytes(base64.b64decode(entry["bytes_base64"]))
            self.security.restore(path, entry["owner_dacl_sddl"])
        for name, entry in sorted(snapshot.items(), key=lambda item: -len(Path(item[0]).parts)):
            self.attrs.set(self.root / name, entry["attributes"])
        actual = self.snapshot()
        T.require(comparable(actual) == comparable(snapshot),
                  "Restore mismatch in bytes/raw attributes/owner/DACL; client was not run.")
        return actual


def finish_stub(record, executable):
    """Wait for the eight-second recording stub even when its parent client failed."""
    if not record.exists():
        return []
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.QueryFullProcessImageNameW.argtypes = [ctypes.c_void_p, ctypes.c_uint32,
                                                ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_uint32)]
    kernel.QueryFullProcessImageNameW.restype = ctypes.c_int
    kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    kernel.WaitForSingleObject.restype = ctypes.c_uint32
    kernel.TerminateProcess.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    kernel.TerminateProcess.restype = ctypes.c_int
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel.CloseHandle.restype = ctypes.c_int
    results = []
    for line in record.read_text(encoding="utf-8").splitlines():
        pid = int(json.loads(line)["pid"])
        handle = kernel.OpenProcess(0x100000 | 0x1000 | 1, False, pid)
        if not handle:
            error = ctypes.get_last_error()
            T.require(error == 87, f"Could not inspect recording stub {pid}: WinError {error}")
            results.append({"pid": pid, "already_exited": True})
            continue
        try:
            if kernel.WaitForSingleObject(handle, 0) == 0:
                results.append({"pid": pid, "already_exited": True})
                continue
            size = ctypes.c_uint32(32768)
            path = ctypes.create_unicode_buffer(size.value)
            if not kernel.QueryFullProcessImageNameW(handle, 0, path, ctypes.byref(size)):
                raise ctypes.WinError(ctypes.get_last_error())
            T.require(Path(path.value).resolve() == executable.resolve(),
                      "Recorded PID belongs to another executable; refusing to terminate it.")
            status = kernel.WaitForSingleObject(handle, 12000)
            if status == 258:
                if not kernel.TerminateProcess(handle, 1):
                    raise ctypes.WinError(ctypes.get_last_error())
                T.require(kernel.WaitForSingleObject(handle, 5000) == 0, "Stub cleanup timed out.")
            else:
                T.require(status == 0, "Could not wait for the recording stub.")
            results.append({"pid": pid, "forced_termination": status == 258})
        finally:
            kernel.CloseHandle(handle)
    return results


class Pair:
    def __init__(self, args, root, env, executable, evidence, attrs):
        self.args, self.root, self.env = args, root, env
        self.executable, self.evidence, self.attrs = executable, evidence, attrs
        self.steam = root / "Steam"
        self.game = self.steam / "steamapps" / "common" / "Valheim"
        self.game.mkdir(parents=True)
        (self.game / "valheim.exe").write_bytes(b"fixture presence marker; never executed\n")
        (self.steam / "steamapps" / "appmanifest_892970.acf").write_text(
            '"AppState"\n{\n "appid" "892970"\n "installdir" "Valheim"\n}\n', encoding="utf-8")
        (self.steam / "steamapps" / "libraryfolders.vdf").write_text(
            '"libraryfolders"\n{\n "0"\n {\n  "path" "' + str(self.steam).replace("\\", "\\\\")
            + '"\n  "apps"\n  {\n   "892970" "1"\n  }\n }\n}\n', encoding="utf-8")
        self.world = "hidden_pair_" + uuid.uuid4().hex
        self.archives = {revision: T.make_archive(revision) for revision in (1, 2)}
        self.server = T.FixtureServer(self.world, self.archives[1])
        self.origin = f"http://127.0.0.1:{self.server.server_port}"
        self.payload = base64.b64encode(
            f"launch?{self.world}??127.0.0.1?2456?127.0.0.1:{self.server.server_port}?http?0".encode()).decode()
        self.url = "phvalheim://?" + self.payload
        self.cache = Path(env["APPDATA"]) / "PhValheim" / "worlds" / "127.0.0.1" / self.world
        self.cached_world = self.cache / self.world
        self.backend = self.cached_world / "BepInEx" / "phvalheim.backend"
        self.config = self.cached_world / "BepInEx" / "config" / "fixture.cfg"
        self.manifest = self.config.parent / T.POLICY
        self.archive = self.cache / (self.world + ".zip")
        self.sync = self.cache / (self.world + ".sync")
        self.preloader = self.cached_world / "BepInEx" / "core" / "BepInEx.Preloader.dll"
        self.targets = {name: self.game / name for name in T.LOADER}
        self.targets["phvalheim.backend"] = self.backend
        self.targets["fixture.cfg"] = self.config
        self.files = FixtureFiles(root, [self.steam, root / "roaming", root / "local", root / "temp"], attrs)
        self.report = {"passed": False, "gameplay_tested": False, "world": self.world,
                       "origin": self.origin, "url": self.url, "root": str(root),
                       "cache": str(self.cache), "game": str(self.game),
                       "old": {"client": str(args.old_client), "sha256": args.old_sha, "version": "2.0.18"},
                       "new": {"client": str(args.new_client), "sha256": args.new_sha, "version": "2.0.19"},
                       "snapshot_scope": [str(path) for path in self.files.bases],
                       "equality_ignores": ["file_id", "mtime_ns"],
                       "transcript_limit_bytes": T.LIMIT, "cases": {}, "failures": []}

    def save(self):
        T.save_json(self.evidence / "results.json", self.report)

    def check(self, result, condition, message):
        result.setdefault("checks", []).append({"passed": bool(condition), "message": message})
        if not condition:
            self.report["failures"].append(result["label"] + ": " + message)
            print("FAIL: " + result["label"] + ": " + message, flush=True)

    def key(self, path):
        return path.relative_to(self.root).as_posix()

    def run(self, label, side, snapshot=None, unhide=False):
        result = {"label": label, "side": side, "checks": [], "exit_code": None,
                  "served_archive_md5": self.server.md5,
                  "served_archive_sha256": hashlib.sha256(self.server.archive).hexdigest()}
        self.report["cases"][label] = result
        folder = self.evidence / label
        folder.mkdir()
        record = folder / "steam.jsonl"
        output_path = folder / "stdout.txt"
        start = len(self.server.requests)
        output = ""
        print("Running " + label, flush=True)
        try:
            if snapshot is not None:
                restored = self.files.restore(snapshot)
                T.save_json(folder / "restored.json", restored)
                result["restored_case_equal"] = comparable(restored) == comparable(snapshot)
                if unhide:
                    expected = comparable(snapshot)
                    for name, entry in expected.items():
                        if entry["kind"] == "file" and entry["attributes"] & T.HIDDEN:
                            value = entry["attributes"] & ~T.HIDDEN
                            self.attrs.set(self.root / name, value)
                            entry["attributes"] = value or T.NORMAL
                    actual = self.files.snapshot()
                    T.require(comparable(actual) == expected,
                              "Unhide control changed more than Hidden (bytes/ReadOnly/owner/DACL).")
                    result["only_hidden_cleared"] = True
            before = self.files.snapshot()
            T.save_json(folder / "before.json", before)
            result["before"] = label + "/before.json"
            client = getattr(self.args, side + "_client")
            digest = T.sha256(client)
            result["exe_sha256"] = digest
            T.require(digest == getattr(self.args, side + "_sha"), "EXE changed before execution.")
            env = dict(self.env, PHV_TEST_STEAM_LOG=str(record))
            result["command"] = [str(client), self.url]
            result["exit_code"], output = T.run_process(result["command"], self.root, env,
                                                       self.args.timeout, output_path)
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
            result["harness_error"] = str(error)
            self.check(result, False, "Execution/restore failure: " + str(error))
            output = T.tail(output_path)
        finally:
            try:
                result["stub_cleanup"] = finish_stub(record, self.executable)
                self.check(result, not any(item.get("forced_termination") for item in result["stub_cleanup"]),
                           "Recording stub exited within its normal bounded lifetime")
            except (OSError, RuntimeError, ValueError) as error:
                self.check(result, False, "Stub cleanup: " + str(error))
            result["requests"] = self.server.requests[start:]
            result["steam"] = T.tail(record)
            T.save_json(folder / "requests.json", result["requests"])
            log = Path(self.env["APPDATA"]) / "PhValheim" / "logs" / "phvalheim-client.log"
            (folder / "client.log").write_text(T.tail(log), encoding="utf-8")
            for index, fallback in enumerate(sorted((self.root / "temp").glob("PhValheim-*/logs/phvalheim-client.log"))):
                (folder / f"fallback-{index}.log").write_text(T.tail(fallback), encoding="utf-8")
            try:
                after = self.files.snapshot()
                T.save_json(folder / "after.json", after)
                result["after"] = label + "/after.json"
                result["lifecycle"] = {
                    name: {"before_id": before.get(name, {}).get("file_id"),
                           "after_id": after.get(name, {}).get("file_id"),
                           "before_attributes": before.get(name, {}).get("attributes"),
                           "after_attributes": after.get(name, {}).get("attributes")}
                    for name in sorted(set(before) | set(after))
                    if before.get(name) != after.get(name)}
            except (OSError, RuntimeError, UnboundLocalError) as error:
                self.check(result, False, "Snapshot failure: " + str(error))
            self.save()
        version = "2.0.18" if side == "old" else "2.0.19"
        self.check(result, re.search(r"PhValheim Client " + re.escape(version) + r"(?:\s|$)", output),
                   "Observed actual " + version + " banner")
        result["operation_failed"] = (not result["steam"] and result["exit_code"] is not None
                                      and (result["exit_code"] != 0 or "ERROR" in output))
        result["measured_outcome"] = (
            "harness_failure" if result.get("harness_error") else
            "operation_failure_without_handoff" if result["operation_failed"] else
            "steam_handoff_recorded" if result["steam"] else "no_handoff_without_reported_failure")
        print(label + ": " + result["measured_outcome"] + "; exit=" + str(result["exit_code"]), flush=True)
        self.save()
        return result, output, record

    def success(self, run, revision, personal="kept", update=False):
        result, output, record = run
        self.check(result, result["exit_code"] == 0 and "ERROR" not in output,
                   "Successful client operation")
        self.check(result, "Valheim has closed. See you next time." in output
                   and "could not observe the game through to its exit" not in output,
                   "Client observed normal game-lifetime stub exit")
        try:
            T.check_launch(record, self.payload, self.preloader)
        except (OSError, RuntimeError, ValueError) as error:
            self.check(result, False, str(error))
        for name, content in {**T.LOADER, "phvalheim.backend": self.origin.encode()}.items():
            path = self.targets[name]
            self.check(result, path.is_file() and path.read_bytes() == content, "Correct bytes: " + name)
        self.check(result, self.config.is_file() and re.search(
            r"(?m)^managed\s*=\s*rev" + str(revision) + r"\s*$", self.config.read_text(encoding="utf-8")),
            "Managed config updated to rev" + str(revision))
        self.check(result, self.config.is_file() and re.search(
            r"(?m)^personal\s*=\s*" + re.escape(personal) + r"\s*$", self.config.read_text(encoding="utf-8")),
            "Personal config retained: " + personal)
        self.check(result, self.archive.is_file() and self.archive.read_bytes() == self.archives[revision],
                   "Cached archive equals served revision")
        self.check(result, self.manifest.is_file() and self.manifest.read_bytes() == T.policy(revision),
                   "Installed policy equals served revision")
        self.check(result, self.sync.is_file() and self.sync.read_text(encoding="utf-8").splitlines()
                   == ["worldMd5=" + self.server.md5, "modsMd5=", "configMd5="],
                   "Sync record describes served revision")
        downloaded = any(urlsplit(path).path.endswith(".zip") for path in result["requests"])
        self.check(result, downloaded == update, "Expected archive download" if update else "Reused seeded archive")

    def denied(self, run, targets):
        result, _, _ = run
        self.check(result, result["operation_failed"], "Operation failed with no Steam handoff")
        self.check(result, any("mode=getMD5" in request for request in result["requests"]),
                   "Reached fixture checksum operation")
        before = json.loads((self.evidence / result["before"]).read_text(encoding="utf-8"))
        after = json.loads((self.evidence / result["after"]).read_text(encoding="utf-8"))
        for path in targets:
            key = self.key(path)
            self.check(result, key in after and comparable({key: before[key]}) == comparable({key: after[key]}),
                       "Denied target bytes/attributes/owner/DACL preserved: " + key)

    def retained_hidden(self, run, paths):
        result = run[0]
        before = json.loads((self.evidence / result["before"]).read_text(encoding="utf-8"))
        for path in paths:
            self.check(result, path.is_file() and bool(self.attrs.get(path) & T.HIDDEN),
                       "Hidden retained: " + self.key(path))
            self.check(result, path.is_file()
                       and self.attrs.get(path) == before[self.key(path)]["attributes"],
                       "Raw attributes retained: " + self.key(path))

    def prepare(self, name):
        self.files.restore(self.seed)
        self.attrs.seed(self.config, b"[Fixture]\nmanaged = stale\npersonal = kept\n", 0)
        if name == "ordinary" or name.startswith("all-hidden"):
            for key in ("winhttp.dll", "doorstop_config.ini", "phvalheim.backend"):
                self.attrs.seed(self.targets[key], ("old sentinel: " + key).encode(), 0)
        if name.startswith("all-hidden"):
            for path in self.files.paths():
                if path.is_file():
                    self.attrs.set(path, (self.attrs.get(path) & ~T.NORMAL) | T.HIDDEN)
        elif name != "ordinary":
            key = {"hidden-dll": "winhttp.dll", "hidden-doorstop": "doorstop_config.ini",
                   "hidden-backend": "phvalheim.backend", "hidden-config": "fixture.cfg",
                   "readonly-dll": "winhttp.dll", "readonly-config-update": "fixture.cfg"}[name]
            content = (self.config.read_bytes() if key == "fixture.cfg"
                       else ("old sentinel: " + key).encode())
            flags = T.HIDDEN | (T.READONLY if name.startswith("readonly") else 0)
            self.attrs.seed(self.targets[key], content, flags)
        revision = 2 if name.endswith("update") else 1
        self.server.archive = self.archives[revision]
        self.server.md5 = hashlib.md5(self.server.archive).hexdigest()
        snapshot = self.files.snapshot()
        T.save_json(self.evidence / (name + "-case.json"), snapshot)
        return snapshot, revision

    def exercise(self):
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        try:
            with T.steam_registry(self.steam, self.executable):
                run = self.run("seed-218", "old")
                self.success(run, 1, personal="default", update=True)
                T.require(not self.report["failures"], "2.0.18 clean seed failed; no valid paired fixture.")
                self.seed = self.files.snapshot()
                T.require(all(not entry["attributes"] & (T.HIDDEN | T.READONLY)
                              for entry in self.seed.values() if entry["kind"] == "file"),
                          "Clean seed unexpectedly contains Hidden/ReadOnly files.")
                T.save_json(self.evidence / "original-seed.json", self.seed)
                self.report["seed_snapshot_sha256"] = T.sha256(self.evidence / "original-seed.json")
                cases = ("ordinary", "hidden-dll", "hidden-doorstop", "hidden-backend", "hidden-config",
                         "all-hidden", "all-hidden-update", "readonly-dll", "readonly-config-update")
                all_hidden = None
                for name in cases:
                    try:
                        snapshot, revision = self.prepare(name)
                        if name == "all-hidden":
                            all_hidden = snapshot
                        elif name == "all-hidden-update":
                            T.require(all_hidden is not None and comparable(snapshot) == comparable(all_hidden),
                                      "Full update must start from exactly the all-Hidden relaunch case.")
                            self.report["all_hidden_update_case_equal"] = True
                    except (OSError, RuntimeError, ValueError) as error:
                        self.report["failures"].append(name + ": case preparation: " + str(error))
                        self.save()
                        continue
                    old_failed = False
                    for side in ("old", "new"):
                        try:
                            run = self.run(name + "-" + side, side, snapshot)
                            if side == "old":
                                old_failed = run[0]["operation_failed"]
                            if name == "ordinary":
                                self.success(run, revision)
                            elif name == "readonly-dll":
                                self.denied(run, [self.targets["winhttp.dll"]])
                            elif name == "readonly-config-update":
                                run[0]["old_behavior_is_observation_only"] = side == "old"
                                if side == "new":
                                    self.denied(run, [self.config])
                                    self.check(run[0], any(urlsplit(p).path.endswith(".zip")
                                                          for p in run[0]["requests"]),
                                               "ReadOnly config control reached full update")
                            elif side == "new":
                                self.success(run, revision, update=revision == 2)
                                if name.startswith("all-hidden"):
                                    stable = [self.config, self.sync, *(self.game / key for key in T.LOADER)]
                                    if revision == 1:
                                        stable.extend([self.backend, self.manifest])
                                    self.retained_hidden(run, stable)
                                    run[0]["replacement_note"] = (
                                        "Full update may recreate cached archive, manifest and backend; "
                                        "before/after IDs and attributes are recorded in lifecycle.")
                                else:
                                    hidden = [self.root / key for key, entry in snapshot.items()
                                              if entry["kind"] == "file" and entry["attributes"] & T.HIDDEN]
                                    self.retained_hidden(run, hidden)
                            elif revision == 2:
                                run[0]["old_behavior_is_observation_only"] = True
                            else:
                                target = {"hidden-dll": self.targets["winhttp.dll"],
                                          "hidden-doorstop": self.targets["doorstop_config.ini"],
                                          "hidden-backend": self.backend,
                                          "hidden-config": self.config, "all-hidden": self.config}[name]
                                self.denied(run, [target])
                        except (OSError, RuntimeError, ValueError, KeyError) as error:
                            self.report["failures"].append(name + "-" + side + ": " + str(error))
                        finally:
                            self.save()
                    if name.startswith(("hidden-", "all-hidden")) and (revision == 1 or old_failed):
                        try:
                            run = self.run(name + "-old-unhide-only", "old", snapshot, unhide=True)
                            self.success(run, revision, update=revision == 2)
                        except (OSError, RuntimeError, ValueError, KeyError) as error:
                            self.report["failures"].append(name + ": unhide-only control: " + str(error))
                        finally:
                            self.save()
                self.files.restore(self.seed)
                self.report["final_seed_restored_equal"] = True
                T.require(T.sha256(self.evidence / "original-seed.json") == self.report["seed_snapshot_sha256"],
                          "Original seed evidence changed.")
                self.report["passed"] = not self.report["failures"]
        finally:
            self.save()
            self.server.shutdown()
            self.server.server_close()
            thread.join(timeout=5)
        return self.report["passed"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for side in ("old", "new"):
        parser.add_argument("--" + side + "-client", type=Path, required=True)
        parser.add_argument("--" + side + "-sha", required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=175, help="Per-client seconds, maximum 180")
    args = parser.parse_args()
    evidence = None
    try:
        T.check_native_ci()
        T.refuse_steam()
        T.require(1 <= args.timeout <= 180, "--timeout must be between 1 and 180 seconds.")
        for side in ("old", "new"):
            client = getattr(args, side + "_client").resolve(strict=True)
            digest = getattr(args, side + "_sha").lower()
            T.require(client.is_file() and client.suffix.lower() == ".exe", "Expected extracted Windows EXE.")
            T.require(re.fullmatch(r"[0-9a-f]{64}", digest), "Expected SHA256 digest for " + side)
            T.require(T.sha256(client) == digest, "EXE SHA256 mismatch for " + side)
            setattr(args, side + "_client", client)
            setattr(args, side + "_sha", digest)
        T.require(args.old_sha != args.new_sha, "Old and new EXEs must be distinct published artifacts.")
        evidence = args.evidence_dir.resolve()
        evidence.mkdir(parents=True, exist_ok=False)
        print("Evidence: " + str(evidence), flush=True)
        attrs = T.Attributes()
        with tempfile.TemporaryDirectory(prefix="phv-hidden-pair-") as temporary:
            root = Path(temporary)
            T.require(not evidence.is_relative_to(root), "Evidence must be outside restored fixture files.")
            env = {name: value for name, value in os.environ.items()
                   if not name.upper().startswith(("PHVALHEIM_", "PHV_TEST_", "DOTNET_", "CORECLR_", "COR_"))}
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
                executable, known_folder = T.build_stub(root, env, evidence)
                with T.isolate_diagnostics(known_folder, Path(env["APPDATA"]), root, env, evidence):
                    pair = Pair(args, root, env, executable, evidence, attrs)
                    passed = pair.exercise()
            finally:
                for directory, dirs, files in os.walk(root):
                    for name in dirs + files:
                        path = Path(directory) / name
                        attrs.set(path, attrs.get(path) & ~(T.HIDDEN | T.READONLY))
        print(("PASS" if passed else "FAIL") + ": published 2.0.18/2.0.19 paired regression; "
              "see results.json. Steam handoff only; no gameplay.", flush=True)
        return 0 if passed else 1
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        if evidence is not None and evidence.is_dir():
            (evidence / "failure.txt").write_text(str(error)[:T.LIMIT] + "\n", encoding="utf-8")
        print("FAIL: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
