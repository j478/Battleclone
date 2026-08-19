#!/usr/bin/env bash
# Serves the exported Web build over plain HTTP so it can be opened in a
# browser (Godot's WASM build won't run from a file:// URL). Threading is
# disabled in the export preset specifically so no COOP/COEP headers are
# needed here — a plain static server is enough.
set -euo pipefail
cd "$(dirname "$0")/../build/web"

PORT="${1:-8060}"
echo "Serving build/web at http://localhost:$PORT"
exec python3 -m http.server "$PORT"
