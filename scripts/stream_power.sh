#!/bin/bash
# Power state of the session while nobody is streaming.
#   low  - close running games and turn the display off. Hyprland and Steam keep running,
#          so Steam still downloads updates, but the GPU idles.
#   wake - turn the display back on before a stream starts.
#   boot - go low after startup unless a stream started in the meantime.

LOG=/tmp/sunshine_switch.log
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

set_dpms() {
    pgrep -x Hyprland > /dev/null || return 0
    $HYPRCTL eval "hl.dispatch(hl.dsp.dpms({ action = \"$1\" }))" >> $LOG 2>&1
}

case "$1" in
    low)
        echo "[$(date)] Entering low-power mode (Steam keeps running)" >> $LOG
        close_games
        set_dpms off
        ;;
    wake)
        set_dpms on
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
