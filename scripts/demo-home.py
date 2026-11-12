#!/usr/bin/env python3
"""Makes a pretend home folder for trying the app (and taking the README screenshots) on a
computer without any port installed: Pinyon Shift installed, FIFA Street with an update, Saints
Reborn building, the rest not installed, and the newest releases already looked up.

    python3 scripts/demo-home.py /tmp/demo-home      # prints the pid of the pretend build
    HOME=/tmp/demo-home ARMADA_PORTS_BACKEND=<folder with armadaports.py and ports.json> godot ...
"""
import json
import os
import subprocess
import sys
import time

home = os.path.abspath(sys.argv[1])
share = os.path.join(home, '.local', 'share')
root = os.path.join(share, 'armada-ports')


def put(path, text='', mode=0o644):
    path = os.path.join(home, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)
    os.chmod(path, mode)


# Pinyon Shift v0.8.2, built
src = '.local/share/PinyonShift/source/0.1.1'
put(f'{src}/config/release.json', json.dumps({'version': '0.8.2'}))
put(f'{src}/tools/pinyon.py', 'print("demo")\n')
put(f'{src}/out/build/linux-arm64-release/pinyon_shift', '', 0o755)
put(f'{src}/.local/game/base/default.xex', 'xex')
put(f'{src}/.local/pinyon-shift.sh', '#!/bin/sh\necho "Pinyon Shift (demo)"; sleep 2\n', 0o755)

# FIFA Street 1.3.0, built, an update is out
data = '.local/share/FifaStreet-arm64'
put(f'{data}/game/fifastreet.sh', '#!/bin/sh\necho "FIFA Street (demo)"; sleep 2\n', 0o755)
put(f'{data}/GameData/default.xex', 'xex')
put('.local/share/armada-ports/launchers/fifa-street/fifastreet-launcher', '#!/bin/sh\necho 1.3.0\n', 0o755)

# Disc images to pick from
for name, size in (('Forza Horizon (USA).iso', 7 << 30), ('Midnight Club - Los Angeles.iso', 7 << 30),
                   ('Skate 3.iso', 6 << 30)):
    path = os.path.join(home, 'Downloads', name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.truncate(size)

notes = {
    'pinyon-shift': "## What's new\n\n- Rebased on upstream v0.8.2: prebuilt ShiftGlue kits, Mods panel, F7 achievements.\n- Smaller sysroot: the first build downloads less.\n\n## Install\n...",
    'fifa-street': "## What's new\n\n- Steady 60 fps on the RP6 with the ARMv8.2 engine flags.\n- Update rebuilds only what changed.\n",
    'saints-reborn': "## What's new\n\n- Rebased on SaintsReborn main.\n- GPU Tweaks on by default.\n",
    'skate3-recomp': "## What's new\n\n- First release: builds Skate 3 on the handheld from your disc image.\n- Native Vulkan renderer, GTK3 sysroot.\n",
}
versions = {'pinyon-shift': '0.8.2', 'fifa-street': '1.4.0', 'saints-reborn': '0.4.1', 'mm3-recomp': '0.1.12',
            'rusty-mcla': '0.3.1', 'fh2-recompiled': '0.1.0', 'skate3-recomp': '0.1.0', 'road-trip': '0.1.0',
            'reskate': '0.8.0', 'azimuth': '0.2.0'}
state = {
    'checked': time.time(),
    'ports': {'pinyon-shift': {'steam_appid': 3000000001}},
    'latest': {pid: {'tag': f'v{v}', 'version': v, 'url': 'https://example.invalid/x.tar.gz', 'sha256': None,
                     'size': 1, 'page': '', 'published': '2026-11-10T10:00:00Z', 'notes': notes.get(pid, '')}
               for pid, v in versions.items()},
}
os.makedirs(root, exist_ok=True)
with open(os.path.join(root, 'state.json'), 'w') as f:
    json.dump(state, f, indent=2)

# Saints Reborn building, held by a sleeping process
sleeper = subprocess.Popen(['sleep', '3600'], start_new_session=True, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
log = os.path.join(root, 'logs', 'saints-reborn-demo.log')
os.makedirs(os.path.dirname(log), exist_ok=True)
with open(log, 'w') as f:
    f.write('==> Building Saints Reborn\n[812/2410] Building CXX object src/CMakeFiles/saintsrow.dir/rex/ppc_recomp.31.cpp.o\n'
            '[813/2410] Building CXX object src/CMakeFiles/saintsrow.dir/rex/ppc_recomp.32.cpp.o\n'
            '[814/2410] Building CXX object src/CMakeFiles/saintsrow.dir/rex/ppc_recomp.33.cpp.o\n')
job = {'id': 'saints-reborn', 'action': 'install', 'state': 'running', 'stage': 'Compiling the game',
       'percent': 34, 'message': '', 'log': log, 'started': time.time(), 'finished': None, 'pid': sleeper.pid,
       'unit': 'demo', 'home': home, 'plugin_dir': '', 'release': state['latest']['saints-reborn']}
os.makedirs(os.path.join(root, 'jobs'), exist_ok=True)
with open(os.path.join(root, 'jobs', 'saints-reborn.json'), 'w') as f:
    json.dump(job, f)
print(sleeper.pid)
