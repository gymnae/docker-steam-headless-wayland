#!/bin/bash
# Restarts Steam when it runs with no window left.
# There is no tray in this session: closing the Steam window with X hides Steam instead of
# quitting it, so the restart loop in hyprland.lua never runs and the stream shows a black screen.
# Here Steam is shut down instead; that loop then clears its leftovers and starts Big Picture again.
# Runs inside Hyprland as the steam user (started from hyprland.lua).

GRACE=6        # seconds without a window before the restart
INTERVAL=2

# The client binary itself; /usr/bin/steam and steam.sh are only wrappers around it
steam_pid() {
    pgrep -u steam -f 'ubuntu12_32/steam( |$)' | head -n1
}

has_window() {
    hyprctl clients 2>/dev/null | grep -qiE '^[[:space:]]*class: (steam|steamwebhelper)$'
}

game_running() {
    pgrep -f "reaper SteamLaunch" > /dev/null
}

armed_pid=""
missing=0

while true; do
    sleep "$INTERVAL"
    pid=$(steam_pid)
    [ -n "$pid" ] || { armed_pid=""; missing=0; continue; }

    # Only act after this Steam instance showed a window once, so its startup and updates are left alone
    if has_window; then
        armed_pid="$pid"
        missing=0
        continue
    fi
    [ "$armed_pid" = "$pid" ] || continue
    # A game keeps the screen busy; Steam may stay hidden behind it
    if game_running; then
        missing=0
        continue
    fi

    missing=$((missing + INTERVAL))
    [ "$missing" -ge "$GRACE" ] || continue

    echo "--- [Steam Guard] Steam has no window left, restarting it ---"
    kill -TERM "$pid" 2>/dev/null
    for _ in $(seq 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    kill -9 "$pid" 2>/dev/null
    armed_pid=""
    missing=0
done
