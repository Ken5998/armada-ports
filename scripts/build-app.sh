#!/usr/bin/env bash
# Builds the Armada Ports app (app/, a Godot project) for linux-arm64 into out/app/armada-ports:
# one program with its data inside. Works on any x86-64 or arm64 Linux; Godot and the arm64
# export template are downloaded once into ~/.cache/armada-ports-godot.
#
#   scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

version=4.7.2-stable
base="https://github.com/godotengine/godot/releases/download/$version"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/armada-ports-godot/$version"
templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version/-/.}"
case "$(uname -m)" in
    x86_64) editor_name="Godot_v${version}_linux.x86_64" ;;
    aarch64) editor_name="Godot_v${version}_linux.arm64" ;;
    *) echo "unsupported machine $(uname -m)" >&2; exit 1 ;;
esac
mkdir -p "$cache" "$templates"

editor="$cache/$editor_name"
if [[ ! -x $editor ]]; then
    curl -fsSL -o "$cache/SHA512-SUMS.txt" "$base/SHA512-SUMS.txt"
    curl -fsSL -o "$cache/$editor_name.zip" "$base/$editor_name.zip"
    (cd "$cache" && grep " $editor_name.zip\$" SHA512-SUMS.txt | sha512sum --check --quiet)
    unzip -oq "$cache/$editor_name.zip" -d "$cache"
    rm -f "$cache/$editor_name.zip"
    chmod +x "$editor"
fi
if [[ ! -f $templates/linux_release.arm64 ]]; then
    python3 scripts/fetch-godot-template.py "$base/Godot_v${version}_export_templates.tpz" \
        templates/linux_release.arm64 "$templates/linux_release.arm64"
fi

mkdir -p out/app
rm -f out/app/armada-ports
# The first run imports the fonts and images; the export then packs them into the program.
"$editor" --headless --path app --import >/dev/null 2>&1 || true
"$editor" --headless --path app --export-release "Linux arm64" "$PWD/out/app/armada-ports" 2>&1 \
    | grep -Ev '^\s*$|savepack|Storing File' || true
[[ -s out/app/armada-ports ]] || { echo "export failed: no out/app/armada-ports" >&2; exit 1; }
file out/app/armada-ports 2>/dev/null || ls -l out/app/armada-ports
