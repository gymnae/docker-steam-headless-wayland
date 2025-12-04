#!/bin/bash
set -e

# --- 1. Fix Permissions (Running as Root) ---
echo "Fixing permissions..."
# Fix the volume mount ownership so 'steam' can write config files
chown -R steam:steam /home/steam/.config
chown -R steam:steam /home/steam/.steam

# Allow access to GPU devices (Fixes GID mismatch issues)
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true

# --- 2. Setup Runtime Directory ---
# PipeWire requires this directory to be owned by the user (ID 1000)
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

# --- 3. Start System DBus ---
echo "Starting System DBus..."
mkdir -p /run/dbus
dbus-daemon --system --fork

# --- 4. Start Session DBus (As Steam) ---
# We spawn the session bus AS the user 'steam' and capture the address
echo "Starting Session DBus..."
DBUS_ENV=$(su - steam -c "dbus-launch --sh-syntax")
eval "$DBUS_ENV"
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SYSTEM_BUS_ADDRESS

# --- 5. Start Services (As Steam) ---
# We use 'su - steam -c' or 'sudo -u steam' to run everything as the user

echo "Starting Audio Stack..."
# We explicitly pass the environment variables we just generated
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

echo "Linking Compatibility Tools..."
mkdir -p /home/steam/.steam/root/compatibilitytools.d
find /usr/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;
chown -R steam:steam /home/steam/.steam/root/compatibilitytools.d

echo "Starting Sunshine..."
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && sunshine" &

echo "Starting Gamescope..."
# Exec into gamescope as 'steam', preserving the DBus environment
exec sudo -E -u steam gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --force-grab-cursor \
    -- \
    steam -gamepadui -tenfoot
