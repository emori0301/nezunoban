#!/bin/bash
# テクスチャとモデルを全部作り直し、プレビューを撮って Godot に取り込む。
#
#   bash tools/blender/build_all.sh            全部
#   bash tools/blender/build_all.sh --no-render プレビューを撮らない(速い)
#
set -euo pipefail

BLENDER=/opt/homebrew/bin/blender
GODOT=/opt/homebrew/bin/godot
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RENDER=1
for a in "$@"; do
  [ "$a" = "--no-render" ] && RENDER=0
done

run() {
  echo "=== $1 ==="
  "$BLENDER" --background --python "tools/blender/$1" 2>&1 \
    | grep -viE "^blender|blendermcp|^$|^INFO|\| INFO|DeprecationWarning|^  w\.|^  mat\." || true
}

run gen_textures.py
run build_ritual.py
run build_furniture.py
run build_props.py
run build_arch.py
run build_chars.py

if [ "$RENDER" = "1" ]; then
  echo "=== decal_sheet.py ==="
  "$BLENDER" --background --python tools/blender/decal_sheet.py 2>&1 | grep -E "decals sheet" || true
  echo "=== coffin_window_test.py ==="
  "$BLENDER" --background --python tools/blender/coffin_window_test.py 2>&1 \
    | grep -E "coffin window proof|body_face world" || true
  echo "=== render_previews.py ==="
  "$BLENDER" --background --python tools/blender/render_previews.py 2>&1 \
    | grep -E "^engine|^  preview|^  anim |^contact_sheet|^anim_sheet|FAILED" || true
fi

echo "=== godot import ==="
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
echo "=== godot check ==="
"$GODOT" --headless --path . --script res://tools/blender/check_in_godot.gd 2>&1 \
  | grep -viE "^\[|Godot Engine|^$" || true
