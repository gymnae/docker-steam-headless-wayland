#!/bin/bash
# CRITICAL FIX: Do NOT use 'set -e' here. We want the loop to survive temporary errors.

echo "--- [Watchdog] Started ---"

LAST_COUNT=0
export XDG_RUNTIME_DIR=/run/user/1000

# Fallback for the udev rule: mirror the host's hidraw devices into the container's /dev
sync_hidraw() {
    for sys in /sys/class/hidraw/hidraw*; do
        [ -e "$sys/dev" ] || continue
        node="/dev/${sys##*/}"
        IFS=: read -r maj min < "$sys/dev"
        if [ ! -c "$node" ] || [ "$(stat -c '%t:%T' "$node")" != "$(printf '%x:%x' "$maj" "$min")" ]; then
            rm -f "$node"
            mknod -m 0666 "$node" c "$maj" "$min"
        fi
    done
    for node in /dev/hidraw*; do
        [ -e "/sys/class/hidraw/${node##*/}" ] || rm -f "$node"
    done
}

while true; do
    # 1. Hotplug Detection (Input Devices)
    NEW_COUNT=$(ls -1 /dev/input | wc -l)
    if [ "$NEW_COUNT" != "$LAST_COUNT" ]; then
        udevadm trigger --action=change --subsystem-match=input
        LAST_COUNT=$NEW_COUNT
    fi
    
    sync_hidraw

    # 2. Enforce Permissions (Crucial for hotplugged controllers)
    # Only touch nodes that need it: Proton watches /dev with inotify, and a blanket chmod every
    # tick makes every running game re-enumerate all controllers every 5 seconds.
    find /dev/input /dev -maxdepth 1 -type c \( -name 'event*' -o -name 'js*' -o -name 'hidraw*' -o -name 'uhid' \) \
        ! -perm 0666 -exec chmod 666 {} + 2>/dev/null || true
    
    # 3. Audio Keep-Alive
    # If the default sink drifts (e.g. pipewire restarts), force it back to Sunshine.
    # Match any Sunshine sink so its own 5.1/7.1 sinks (sink-sunshine-surround*) aren't overridden.
    CURRENT_SINK=$(su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl get-default-sink 2>/dev/null" || true)

    if [[ "$CURRENT_SINK" != *"sunshine"* ]]; then
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl set-default-sink sunshine-stereo 2>/dev/null" || true
    fi

    # 4. Audio Re-Route
    # Proton binds its audio device once at startup. A game (or its launcher) that opened audio while
    # the boot sink was default keeps playing into it after Sunshine switches to its own sink,
    # so Sunshine records silence. Move every stream onto the current default sink.
    runuser -u steam -- env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR bash -c '
        DEFAULT_ID=$(pactl list sinks short 2>/dev/null | awk -v n="$(pactl get-default-sink 2>/dev/null)" "\$2 == n {print \$1}")
        [ -n "$DEFAULT_ID" ] || exit 0
        pactl list sink-inputs short 2>/dev/null | awk -v s="$DEFAULT_ID" "\$2 != s {print \$1}" | while read -r input; do
            pactl move-sink-input "$input" "$DEFAULT_ID" 2>/dev/null && echo "--- [Watchdog] Moved audio stream $input to default sink"
        done
    ' || true

    sleep 5
done