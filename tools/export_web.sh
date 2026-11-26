#!/usr/bin/env bash
# tools/export_web.sh — Export Knight Lore Reimagined for Web (HTML5/Wasm)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build/web"

mkdir -p "$BUILD_DIR"

echo "==> Exporting Knight Lore Reimagined for Web to $BUILD_DIR..."
godot --headless --path "$PROJECT_ROOT" --export-release "Web" "$BUILD_DIR/index.html"

echo "==> Web export complete!"
ls -lh "$BUILD_DIR"

if [[ "${1:-}" == "--serve" ]]; then
    echo "==> Starting local HTTP server at http://localhost:8000 (Press Ctrl+C to stop)..."
    python3 -m http.server 8000 --directory "$BUILD_DIR"
fi
