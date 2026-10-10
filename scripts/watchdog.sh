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
    chmod 666 /dev/input/event* 2>/dev/null || true
    chmod 666 /dev/input/js* 2>/dev/null || true
    chmod 666 /dev/hidraw* 2>/dev/null || true
    chmod 666 /dev/uhid 2>/dev/null || true
    
    # 3. Audio Keep-Alive
    # If the default sink drifts (e.g. pipewire restarts), force it back to Sunshine.
    # Match any Sunshine sink so its own 5.1/7.1 sinks (sink-sunshine-surround*) aren't overridden.
    CURRENT_SINK=$(su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl get-default-sink 2>/dev/null" || true)

    if [[ "$CURRENT_SINK" != *"sunshine"* ]]; then
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl set-default-sink sunshine-stereo 2>/dev/null" || true
    fi
    
    sleep 5
done