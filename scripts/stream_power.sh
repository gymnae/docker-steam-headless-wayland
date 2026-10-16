#!/bin/bash
# Power state of the session while nobody is streaming.
#   low  - close running games and drop the display to a tiny mode. Hyprland and Steam keep
#          running, so Steam still downloads updates, but the GPU idles.
#   wake - restore the session's mode before a stream starts.
#   boot - go low after startup unless a stream started in the meantime.
#
# The display is never turned off (DPMS): with the CRTC off, KMS capture finds no monitor,
# and Sunshine probes the display on connect before the app's prep-cmd can wake it.

LOG=/tmp/sunshine_switch.log
CONFIG_FILE="/home/steam/.config/display_config"
LOW_MODE="${STREAM_LOW_POWER_MODE:-640x480@30}"
HYPRCTL="runuser -u steam -- env XDG_RUNTIME_DIR=/run/user/1000 hyprctl -i 0"

descendants() {
    local child
    for child in $(pgrep -P "$1"); do
        echo "$child"
        descendants "$child"
    done
}

close_games() {
    local pids="" reaper
    # Steam starts every game under 'reaper SteamLaunch AppId=...'
    for reaper in $(pgrep -f "reaper SteamLaunch"); do
        pids="$pids $reaper $(descendants "$reaper")"
    done
    [ -z "${pids// }" ] && return

    echo "    -> Closing running games" >> $LOG
    kill -TERM $pids 2>/dev/null
    for _ in $(seq 20); do
        kill -0 $pids 2>/dev/null || return
        sleep 0.5
    done
    kill -KILL $pids 2>/dev/null
}

# Hyprland picks the nearest mode when the dummy plug's EDID doesn't offer this one
set_mode() {
    pgrep -x Hyprland > /dev/null || return 0
    $HYPRCTL eval "hl.monitor({ output = \"\", mode = \"$1\", position = \"auto\", scale = \"1\"$2 })" >> $LOG 2>&1
}

restore_mode() {
    local WIDTH=1920 HEIGHT=1080 REFRESH=60 HDR_ENABLED=false extra=""
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    # Same HDR settings as hyprland.lua
    [ "$HDR_ENABLED" = "true" ] && extra=", bitdepth = 10, cm = \"hdr\", sdrbrightness = 1.2, sdrsaturation = 0.98"
    set_mode "${WIDTH}x${HEIGHT}@${REFRESH}" "$extra"
}

case "$1" in
    low)
        echo "[$(date)] Entering low-power mode (Steam keeps running)" >> $LOG
        close_games
        set_mode "$LOW_MODE"
        ;;
    wake)
        restore_mode
        # Give the CRTC a frame before Sunshine starts capturing
        sleep 1
        ;;
    boot)
        # Sunshine probes the display at startup, so leave it on until that is done.
        # The idle watcher is the app's command, so it only runs while a stream is active.
        sleep 60
        pgrep -f idle_watch.py > /dev/null || "$0" low
        ;;
    *)
        echo "Usage: $0 low|wake|boot" >&2
        exit 1
        ;;
esac
