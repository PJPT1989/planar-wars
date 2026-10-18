#!/usr/bin/env bash
# Runs scripts/autotest.gd under a virtual display and saves screenshots (default /tmp/pw-shots).
set -e
cd "$(dirname "$0")/.."
DIR="${1:-/tmp/pw-shots}"
mkdir -p "$DIR"
timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 -- --autotest --shots="$DIR" 2>&1 | grep -v "ALSA\|alsa" | tee "$DIR/log.txt"
