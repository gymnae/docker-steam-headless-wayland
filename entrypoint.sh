#!/bin/bash

# 1. Start Audio Subsystem (PipeWire)
# Steam Remote Play and Sunshine rely on this for sound.
/usr/bin/pipewire &
/usr/bin/pipewire-pulse &
/usr/bin/wireplumber &

# 2. Link Compatibility Tools
# We look for ANY folder in the system compatibility directory.
# This will catch 'proton-cachyos' (from repo) and 'GE-Proton-X-X' (from curl).
echo "--- Linking Proton Versions ---"
mkdir -p /home/steam/.steam/root/compatibilitytools.d
find /usr/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec echo "Found and Linking: {}" \; \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;
echo "-------------------------------"

# 3. Start Sunshine (Wayland Mode)
# Runs in background, capturing the Gamescope output.
sunshine &

# 4. Start Gamescope (Pure Wayland Environment)
# Pinned to 1440p (2560x1440) for performance balance.
# -F fsr : Enables FSR upscaling if you run a game at 1080p inside this 1440p container.
echo "Starting Gamescope..."
exec gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --force-grab-cursor \
    -- \
    steam -gamepadui -tenfoot
