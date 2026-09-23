#!/bin/sh
# macOS アプリを書き出す(out/build/NezuNoBan.app)。export テンプレート 4.7.1 が導入済みであること。
cd "$(dirname "$0")" || exit 1
/opt/homebrew/bin/godot --headless --path . --import >/dev/null 2>&1
/opt/homebrew/bin/godot --headless --path . --export-release "macOS" out/build/NezuNoBan.app
