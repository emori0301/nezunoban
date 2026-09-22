#!/bin/sh
# 寝ずの番 | The Wake を起動する(Godot 4.7.1 が /opt/homebrew/bin/godot にある前提)
cd "$(dirname "$0")" || exit 1
exec /opt/homebrew/bin/godot --path . "$@"
