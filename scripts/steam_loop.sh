#!/bin/bash
# Keeps Steam running: starts Big Picture, and after Steam exits clears its leftovers and starts it again.
# Runs inside Hyprland as the steam user (started from hyprland.lua).
# This must be a script file: "pkill -f" below matches full command lines, and an inline
# 'bash -c "...steamwebhelper..."' loop would match its own pattern and kill itself.

while true; do
    steam -gamepadui -noverifyfiles -fulldesktopres
    echo "--- [Steam Loop] Steam exited, cleaning up and restarting ---"
    sleep 2
    pkill -9 -u steam -f "steamwebhelper|steam-runtime"
    killall -9 steam steam-runtime-supervisor 2>/dev/null
    rm -f /home/steam/.steam/steam.pid /home/steam/.steam/steam.pipe
    sleep 2
done
