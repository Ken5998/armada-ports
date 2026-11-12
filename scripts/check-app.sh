#!/usr/bin/env bash
# Runs the app for a few seconds without a screen, against a pretend home (scripts/demo-home.py),
# and fails on any GDScript error: a quick check that every script still loads and runs.
#
#   scripts/check-app.sh [GODOT]     # default: the editor scripts/build-app.sh downloaded
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${1:-$(find "${XDG_CACHE_HOME:-$HOME/.cache}/armada-ports-godot" -name 'Godot_v*_linux.*' \( -type f -o -type l \) 2>/dev/null | sort | head -n 1)}"
[[ -x $godot ]] || { echo "no Godot editor: run scripts/build-app.sh first" >&2; exit 1; }
tmp="$(mktemp -d)"
pid=""
cleanup() { [[ -n $pid ]] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT
mkdir -p "$tmp/backend"
cp py_modules/armadaports.py ports.json "$tmp/backend/"
pid="$(python3 scripts/demo-home.py "$tmp/home")"
out="$(HOME="$tmp/home" ARMADA_PORTS_BACKEND="$tmp/backend" \
    ARMADA_PORTS_AUTOPILOT="wait:3,right,right,accept,wait:1,back,wait:1,right,accept,wait:1,down,wait:1" \
    timeout 120 "$godot" --headless --path app 2>&1 || true)"
echo "$out" | grep -v '^\s*$' | tail -n 20
if echo "$out" | grep -q 'SCRIPT ERROR\|Parse Error\|Invalid call'; then
    echo "The app has script errors." >&2
    exit 1
fi
echo "App check OK."
