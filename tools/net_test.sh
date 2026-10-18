#!/usr/bin/env bash
# Two copies of the game on this computer play an online match over ENet: a host with an AI seat
# and a guest whose side is played by a bot. Both print a NETTEST line from their own copy of the
# match at the same moment; they must match. Usage: tools/net_test.sh [log dir] [xvfb]
cd "$(dirname "$0")/.."
DIR="${1:-/tmp/pw-net}"
mkdir -p "$DIR"
RUN="godot --headless"
if [ "$2" = "xvfb" ]; then RUN="xvfb-run -a godot --rendering-driver opengl3"; fi
timeout 300 $RUN --path . -- --net=host,start=2,bot,minutes=4 > "$DIR/host.txt" 2>&1 &
sleep 3
timeout 300 $RUN --path . -- --net=join=127.0.0.1,bot > "$DIR/guest.txt" 2>&1
wait
grep -h "NETTEST\|SCRIPT ERROR" "$DIR/host.txt" | sed 's/^/host:  /'
grep -h "NETTEST\|SCRIPT ERROR" "$DIR/guest.txt" | sed 's/^/guest: /'
