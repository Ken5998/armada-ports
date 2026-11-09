#!/usr/bin/env bash
# Packs the built plugin into out/ArmadaPorts-vVERSION.zip (+ .sha256) for Decky.
# Needs dist/index.js (pnpm build).
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(python3 -c 'import json; print(json.load(open("package.json"))["version"])')"
[[ -f dist/index.js ]] || { echo "Missing dist/index.js: run pnpm build first." >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
pkg="$stage/ArmadaPorts"
mkdir -p "$pkg/dist" "$pkg/py_modules"
cp dist/index.js "$pkg/dist/"
cp main.py plugin.json package.json ports.json LICENSE README.md "$pkg/"
cp py_modules/armadaports.py "$pkg/py_modules/"

mkdir -p out
zip_name="ArmadaPorts-v${version}.zip"
rm -f "out/$zip_name"
(cd "$stage" && zip -qr -X "$OLDPWD/out/$zip_name" ArmadaPorts)
(cd out && sha256sum "$zip_name" > "$zip_name.sha256")
echo "Wrote out/$zip_name"
