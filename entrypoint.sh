#!/bin/bash
set -e

# --- 1. Fix Permissions (Crucial for Nested Containers) ---
# We force the device nodes to be accessible. 
# In a perfect world, we'd match GIDs. In the real world, this saves your sanity.
echo "Ensuring GPU permissions..."
sudo chmod 666 /dev/dri/card0 2>/dev/null || true
sudo chmod 666 /dev/dri/renderD* 2>/dev/null || true

# Fix config ownership (Docker volumes often break this)
chown -R steam:steam /home/steam/.config
chown -R steam:steam /home/steam/.steam

# --- 2. Start DBus (Fixes 'Failed to connect to session bus') ---
echo "Starting DBus..."
mkdir -p /run/dbus
sudo dbus-daemon --system --fork

# Start a Session Bus for the 'steam' user
# This is the magic sauce required for PipeWire in headless Docker
export $(dbus-launch)
export DBUS_SESSION_BUS_ADDRESS

# --- 3. Initialize Runtime Dir (Fixes PipeWire 'No such file') ---
export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR

# --- 4. Start Services ---
echo "Starting Audio Stack..."
pipewire &
pipewire-pulse &
wireplumber &

echo "Linking Proton Versions..."
mkdir -p /home/steam/.steam/root/compatibilitytools.d
find /usr/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;

echo "Starting Sunshine..."
sunshine &

echo "Starting Gamescope..."
# We pass the DBus env vars explicitly to Gamescope
exec gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --force-grab-cursor \
    -- \
    steam -gamepadui -tenfoot
