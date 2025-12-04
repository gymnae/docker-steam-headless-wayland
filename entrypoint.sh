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
echo "Starting Gamescope on Dummy Plug..."

# Note: Adjust -W and -H to match your Dummy Plug's capability (e.g., 1920x1080 or 3840x2160)
# -r 60: 60 FPS
# --force-grab-cursor: Ensures mouse stays inside
exec gamescope -W 1920 -H 1080 -r 60 --force-grab-cursor -- steam -gamepadui
