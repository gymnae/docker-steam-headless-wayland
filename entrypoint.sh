#!/bin/bash

# 1. Start Audio (PipeWire)
# Required for audio in both Sunshine and Steam Remote Play
/usr/bin/pipewire &
/usr/bin/pipewire-pulse &
/usr/bin/wireplumber &

# 2. Start Sunshine
# We start it in the background. It will wait for the display to appear.
# On NVIDIA + Dummy Plug, Sunshine uses KMS capture (grabbing the HDMI signal directly).
sunshine &

# 3. Start Gamescope
# We run in "Embedded" mode (-e is implied if no other WM is running).
# We bind it to the resolution of your Dummy Plug (e.g., 1080p or 4k).
# --steam tells Gamescope to treat the nested window as Steam.

echo "Starting Gamescope pinned to 1440p..."

# -W 2560 -H 1440 : The "Internal" game resolution.
# -w 2560 -h 1440 : The "Output" signal sent to the dummy plug.
# -r 60 : Lock to 60Hz.
# -F fsr : Use FSR if the game itself renders lower than 1440p.

exec gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --force-grab-cursor \
    -- \
    steam -gamepadui -tenfoot
