#!/usr/bin/env bash
# Exports the browser build into build/web/ (no threads, so no special server headers needed).
# Downloads Godot's 4.3 export templates the first time (about 1 GB, only the web ones are kept).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
TPL="$HOME/.local/share/godot/export_templates/4.3.stable"
if [ ! -f "$TPL/web_nothreads_release.zip" ]; then
	mkdir -p "$TPL"
	tmp="$(mktemp -d)"
	curl -fsSL -o "$tmp/t.tpz" \
		"https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_export_templates.tpz"
	unzip -q -o "$tmp/t.tpz" 'templates/web_*' 'templates/version.txt' -d "$tmp"
	mv "$tmp"/templates/* "$TPL/"
	rm -rf "$tmp"
fi
mkdir -p "$ROOT/build/web"
# Keep Godot from importing the previous build's images (they would end up inside the next .pck).
touch "$ROOT/build/.gdignore"
rm -f "$ROOT"/build/web/*.import
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$ROOT/build/web/index.html"
cp "$ROOT/tools/web/.htaccess" "$ROOT/tools/web/HOW-TO-UPLOAD.txt" "$ROOT/tools/web/planar-net.js" "$ROOT/build/web/"
echo "web build in $ROOT/build/web ($(du -sh "$ROOT/build/web" | cut -f1))"
