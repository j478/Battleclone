#!/usr/bin/env bash
# Watches scenes/scripts/resources for changes and re-runs the Web export
# automatically, so the browser tab just needs a refresh to see the latest
# build instead of re-running export_web.sh by hand every time.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Watching for changes... (Ctrl+C to stop)"
./tools/export_web.sh debug

fswatch -o -l 1 scenes scripts resources project.godot | while read -r _; do
	echo "Change detected, re-exporting..."
	./tools/export_web.sh debug || echo "Export failed, will retry on next change."
done
