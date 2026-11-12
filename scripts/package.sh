#!/usr/bin/env bash
# Packs the built plugin into out/ArmadaPorts-vVERSION.zip (+ .sha256) for Decky, with the app in
# it. Needs dist/index.js (pnpm build) and out/app/armada-ports (scripts/build-app.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(python3 -c 'import json; print(json.load(open("package.json"))["version"])')"
[[ -f dist/index.js ]] || { echo "Missing dist/index.js: run pnpm build first." >&2; exit 1; }
[[ -f out/app/armada-ports ]] || { echo "Missing out/app/armada-ports: run scripts/build-app.sh first." >&2; exit 1; }
app_version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' app/project.godot)"
[[ $app_version == "$version" ]] || { echo "app/project.godot says $app_version, package.json $version." >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
pkg="$stage/ArmadaPorts"
mkdir -p "$pkg/dist" "$pkg/py_modules"
cp dist/index.js "$pkg/dist/"
cp main.py plugin.json package.json ports.json LICENSE README.md "$pkg/"
cp py_modules/armadaports.py "$pkg/py_modules/"
mkdir -p "$pkg/app/art"
cp out/app/armada-ports app/armada-ports.sh "$pkg/app/"
chmod 755 "$pkg/app/armada-ports" "$pkg/app/armada-ports.sh"
cp app/art/grid.png app/art/hero.png app/art/logo.png app/art/wide.png app/art/icon.png "$pkg/app/art/"
cp app/fonts/OFL.txt "$pkg/app/FONTS-OFL.txt"

mkdir -p out
zip_name="ArmadaPorts-v${version}.zip"
rm -f "out/$zip_name"
(cd "$stage" && zip -qr -X "$OLDPWD/out/$zip_name" ArmadaPorts)
(cd out && sha256sum "$zip_name" > "$zip_name.sha256")
echo "Wrote out/$zip_name"
