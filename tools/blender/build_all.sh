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

# 人物 3 体(npc_boss / npc_son / npc_granddaughter)は MPFB2 製が正本。
# build_chars.py は人物を作らないので、MPFB2 が無ければ既存の glb をそのまま残す。
# 終了コードは背景実行だと当てにならないので、標準出力の印で判定する。
if "$BLENDER" --background --python-expr \
   'import addon_utils; print("MPFB_OK" if addon_utils.enable("bl_ext.user_default.mpfb", default_set=True, persistent=True) else "MPFB_NG")' \
   2>/dev/null | grep -q MPFB_OK; then
  run build_humans_mpfb.py
else
  echo "=== build_humans_mpfb.py: MPFB2 未導入のため飛ばす。"
  echo "    既存の npc_*.glb はそのまま残す(README.md 参照) ==="
fi

# 家族写真・遺影・棺の中の顔は、MPFB 製のキヨをレンダリングして作る。
# 人物の glb が要るので、build_humans_mpfb.py の後に走らせる。
if [ -f assets/models/npc_kiyo.glb ]; then
  run render_photos.py
else
  echo "=== render_photos.py: npc_kiyo.glb が無いので飛ばす(MPFB2 が要る) ==="
fi

if [ "$RENDER" = "1" ]; then
  echo "=== render_faces.py ==="
  "$BLENDER" --background --python tools/blender/render_faces.py 2>&1 \
    | grep -E "^  face|npc_faces" || true
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
