#!/bin/bash
set -e

echo "--- [Watchdog] Started ---"

LAST_COUNT=0
export XDG_RUNTIME_DIR=/run/user/1000

while true; do
    # 1. Hotplug Detection (Input Devices)
    NEW_COUNT=$(ls -1 /dev/input | wc -l)
    if [ "$NEW_COUNT" != "$LAST_COUNT" ]; then
        udevadm trigger --action=change --subsystem-match=input
        LAST_COUNT=$NEW_COUNT
    fi
    
    # 2. Enforce Permissions (Crucial for hotplugged controllers)
    chmod 666 /dev/input/event* 2>/dev/null || true
    chmod 666 /dev/input/js* 2>/dev/null
    chmod 666 /dev/hidraw* 2>/dev/null || true
    chmod 666 /dev/uhid 2>/dev/null || true
    
    # 3. Audio Keep-Alive
    # If the default sink drifts (e.g. pipewire restarts), force it back to Sunshine
    if su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl get-default-sink" | grep -qv "sunshine-stereo"; then
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl set-default-sink sunshine-stereo" 2>/dev/null || true
    fi
    
    sleep 5
done
