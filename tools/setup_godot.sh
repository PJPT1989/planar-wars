#!/usr/bin/env bash
# Installs Godot 4.3 (standard build) as `godot` in ~/.local/bin and imports the project.
# Safe to run repeatedly. Used by the SessionStart hook in .claude/settings.json for
# Claude Code cloud sessions; also works on any Linux x86_64 machine.
set -euo pipefail
VERSION="4.3-stable"
BIN="$HOME/.local/bin"
GODOT="$BIN/godot"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! "$GODOT" --version 2>/dev/null | grep -q "^4.3.stable"; then
	mkdir -p "$BIN"
	tmp="$(mktemp -d)"
	curl -fsSL -o "$tmp/godot.zip" \
		"https://github.com/godotengine/godot/releases/download/$VERSION/Godot_v${VERSION}_linux.x86_64.zip"
	unzip -q -o "$tmp/godot.zip" -d "$tmp"
	mv "$tmp/Godot_v${VERSION}_linux.x86_64" "$GODOT"
	chmod +x "$GODOT"
	rm -rf "$tmp"
fi

# First import builds .godot/ (the asset cache); without it scripts fail to load.
if [ ! -d "$ROOT/.godot/imported" ]; then
	"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
fi
echo "godot $("$GODOT" --version) ready at $GODOT"
