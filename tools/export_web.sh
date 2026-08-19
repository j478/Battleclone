#!/usr/bin/env bash
# Rebuilds the Web (HTML5) export using the "Web" preset baked into
# export_presets.cfg. Run this any time after changing scenes/scripts
# and you want to test in a browser. For continuous rebuilds while
# iterating, use watch_web.sh instead.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/web
EXPORT_MODE="${1:-debug}" # debug (default, faster) or release

if [[ "$EXPORT_MODE" == "release" ]]; then
	godot --headless --export-release "Web" build/web/index.html
else
	godot --headless --export-debug "Web" build/web/index.html
fi

echo "Web export written to build/web/index.html"
