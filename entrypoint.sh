#!/bin/bash

# 1. Start Audio Stack
/usr/bin/pipewire &
/usr/bin/pipewire-pulse &
/usr/bin/wireplumber &

# 2. Link Compatibility Tools (Proton-GE AND Proton-CachyOS)
# We iterate over everything in the system folder and link it to the user folder.
echo "--- Linking Compatibility Tools ---"
mkdir -p /home/steam/.steam/root/compatibilitytools.d
find /usr/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec echo "Linking: {}" \; \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;
echo "-----------------------------------"

# 3. Start Sunshine (Wayland Mode)
sunshine &

# 4. Start Gamescope (Pure Wayland Environment)
# Note: xorg-xwayland is still running in the background for game compatibility,
# but the session itself is Wayland.
echo "Starting Gamescope..."
exec gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --force-grab-cursor \
    -- \
    steam -gamepadui -tenfoot
