#!/usr/bin/env python3
"""Exercise the real Vulkan loader's implicit-layer disable switch, without a GPU.

The tiny library records that the loader tried to load it. It deliberately is not
an overlay implementation. This proves the enable/disable semantics only.
"""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

DISABLE = 'DISABLE_VK_LAYER_VALVE_steam_overlay_1'
ENABLE = 'ENABLE_VK_LAYER_VALVE_steam_overlay_1'

if len(sys.argv) > 1 and sys.argv[1] == '--probe':
    class CreateInfo(ctypes.Structure):
        _fields_ = [('sType', ctypes.c_uint32), ('pNext', ctypes.c_void_p),
                    ('flags', ctypes.c_uint32), ('app', ctypes.c_void_p),
                    ('layerCount', ctypes.c_uint32), ('layers', ctypes.c_void_p),
                    ('extensionCount', ctypes.c_uint32), ('extensions', ctypes.c_void_p)]
    vk = ctypes.CDLL('libvulkan.so.1')
    vk.vkCreateInstance.argtypes = [ctypes.POINTER(CreateInfo), ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    instance = ctypes.c_void_p()
    # Success is not required: the layer is a load marker, not a Vulkan implementation.
    result = vk.vkCreateInstance(ctypes.byref(CreateInfo(sType=1)), None, ctypes.byref(instance))
    if result == 0:
        vk.vkDestroyInstance.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        vk.vkDestroyInstance(instance, None)
    sys.exit(0)

with tempfile.TemporaryDirectory(prefix='phv-vulkan-gate-') as tmp:
    root = Path(tmp)
    source = root / 'layer.c'
    source.write_text('''#include <stdio.h>
#include <stdlib.h>
__attribute__((constructor)) static void loaded(void) {
    FILE *f = fopen(getenv("PHV_LAYER_MARKER"), "w");
    if (f) { fputs("loaded", f); fclose(f); }
}
void *vkGetInstanceProcAddr(void *instance, const char *name) { return NULL; }
''')
    library = root / 'marker.so'
    subprocess.run(['cc', '-shared', '-fPIC', str(source), '-o', str(library)], check=True)
    layers = root / 'vulkan' / 'implicit_layer.d'
    layers.mkdir(parents=True)
    (layers/'test.json').write_text(json.dumps({'file_format_version': '1.0.0', 'layer': {
        'name': 'VK_LAYER_PHVALHEIM_test', 'type': 'GLOBAL', 'library_path': str(library),
        'api_version': '1.0.0', 'implementation_version': '1', 'description': 'test load marker',
        'enable_environment': {ENABLE: '1'}, 'disable_environment': {DISABLE: '1'}}}))
    for value, expected in [('0', False), ('1', False), (None, True)]:
        marker = root/'loaded'
        marker.unlink(missing_ok=True)
        env = dict(os.environ, XDG_DATA_HOME=tmp, PHV_LAYER_MARKER=str(marker))
        env[ENABLE] = '1'
        if value is None:
            env.pop(DISABLE, None)
        else:
            env[DISABLE] = value
        proc = subprocess.run([sys.executable, __file__, '--probe'], env=env, capture_output=True, timeout=30)
        assert proc.returncode == 0, proc.stderr.decode(errors='replace')
        assert marker.exists() == expected, (value, expected, proc.stderr.decode(errors='replace'))
        print(f'PASS real Vulkan loader: disable={value!r}, layer loaded={marker.exists()}')
