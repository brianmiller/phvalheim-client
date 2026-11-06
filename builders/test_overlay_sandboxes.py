#!/usr/bin/env python3
"""Run overlay policy through real Flatpak boundaries with recording game/Steam stubs.
Run in the privileged disposable flatpak test container under dbus-run-session.
Usage: test_overlay_sandboxes.py candidate.flatpak [previous.flatpak]
"""
import base64
import json
import os
from pathlib import Path
import shutil
import sys
import test_flatpak_runtime as T

def command(args):
    return T.sh(args, timeout=300, check=True)

def launches(expect_fixed):
    for policy in ('on', 'off'):
        T.clear_logs()
        payload = base64.b64decode(T.launch_payload_b64(T.WORLD, port, False)).decode() + '?0??fixture-token?overlay=' + policy
        url = 'phvalheim://?' + base64.b64encode(payload.encode()).decode()
        _, out = T.sh(['flatpak', 'run', T.APP_ID, url], timeout=120)
        rec = T.wait_for_json(T.VALHEIM_LOG, timeout=10)
        assert rec is not None, out[-1500:]
        actual = rec['env'].get('DISABLE_VK_LAYER_VALVE_steam_overlay_1')
        expected = (None if expect_fixed else '0') if policy == 'on' else '1'
        assert actual == expected, (policy, expected, actual)
        assert rec['env'].get('ENABLE_VK_LAYER_VALVE_steam_overlay_1') == ('1' if policy == 'on' else '0')
        print(f'PASS overlay={policy}, disable={actual!r}', flush=True)

assert Path('/.dockerenv').is_file(), 'Run only in a disposable Docker test container'
candidate = sys.argv[1]
assert os.environ.get('DISABLE_VK_LAYER_VALVE_steam_overlay_1') == '1', 'Seed the host disable variable to test inherited removal'
T.build_fake_host()
zip_path = T.FAKE / 'world.zip'; T.build_world_zip(zip_path)
srv, port = T.start_fake_server(zip_path, '')
try:
    if len(sys.argv) > 2:
        command(['flatpak', 'install', '--system', '--noninteractive', '--reinstall', sys.argv[2]])
        launches(False)
        print('PASS negative control: previous bundle suppresses enabled overlay with disable=0', flush=True)
    command(['flatpak', 'install', '--system', '--noninteractive', '--reinstall', candidate])
    if os.environ.get('PHV_TEST_STEAM_ONLY') != '1':
        launches(True)
        print('PASS Flatpak client -> host game removes inherited disable=1', flush=True)

    # A minimal Steam-ID fixture in the actual Steam sandbox shape. The SDK supplies
    # Python for our recording game. No real Steam, IPC, GPU or gameplay claim.
    root = Path('/tmp/phv-steam-fixture'); root.mkdir()
    (root/'files/bin').mkdir(parents=True)
    (root/'files/bin/steam').write_text('#!/bin/sh\nexit 0\n')
    (root/'files/bin/steam').chmod(0o755)
    (root/'metadata').write_text('[Application]\nname=com.valvesoftware.Steam\nruntime=org.freedesktop.Sdk/x86_64/25.08\nsdk=org.freedesktop.Sdk/x86_64/25.08\ncommand=steam\n[Context]\nshared=network;ipc;\nfilesystems=home;/run/media;\n[Environment]\nDISABLE_VK_LAYER_VALVE_steam_overlay_1=1\n')
    command(['flatpak', 'build-finish', str(root)])
    command(['flatpak', 'build-export', '/tmp/phv-steam-repo', str(root)])
    command(['flatpak', 'remote-add', '--system', '--if-not-exists', '--no-gpg-verify', 'phv-steam-test', '/tmp/phv-steam-repo'])
    command(['flatpak', 'install', '--system', '--noninteractive', '--reinstall', 'phv-steam-test', 'com.valvesoftware.Steam'])
    command(['flatpak', 'info', 'com.valvesoftware.Steam'])
    steamroot = T.HOME/'.var/app/com.valvesoftware.Steam/.local/share/Steam'
    shutil.copytree(T.HOME/'.steam/steam', steamroot, dirs_exist_ok=True)
    Path('/usr/local/bin/steam').unlink()
    launches(True)
    print('PASS Flatpak client -> Steam sandbox removes app-inherited disable=1', flush=True)
finally:
    srv.shutdown()
    T.sh(['flatpak', 'uninstall', '--system', '--noninteractive', 'com.valvesoftware.Steam', T.APP_ID], timeout=60)
    T.sh(['flatpak', 'remote-delete', '--system', 'phv-steam-test'], timeout=60)
