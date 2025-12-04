#!/bin/bash
set -e

# --- 1. Fix Permissions ---
echo "Fixing permissions..."
# Config Dirs
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config
chown -R steam:steam /home/steam/.steam
chown -R steam:steam /home/steam/.local

# GPU & Input Access (Crucial for Sunshine/Gamescope)
# We make them globally writable to bypass group/user mismatch issues in containers
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true
chmod 666 /dev/uinput 2>/dev/null || true

# --- 2. Setup Runtime & DBus ---
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

# Start System DBus
mkdir -p /run/dbus
dbus-daemon --system --fork

# Start Session DBus (As Steam)
echo "Starting Session DBus..."
DBUS_ENV=$(su - steam -c "dbus-launch --sh-syntax")
eval "$DBUS_ENV"
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SYSTEM_BUS_ADDRESS

# --- 3. Start Seat Daemon (The "No Seat" Fix) ---
# seatd allows Gamescope to access hardware without systemd-logind
echo "Starting seatd..."
seatd -g video -n &
export LIBSEAT_BACKEND=seatd

# --- 4. Start Audio Stack ---
echo "Starting Audio..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# --- 5. Start Gamescope (Backgrounded) ---
echo "Starting Gamescope..."
# We run in background so we can wait for the display socket
sudo -E -u steam HOME=/home/steam gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --force-grab-cursor \
    -- \
    steam -gamepadui -tenfoot &

# Capture Gamescope PID
GS_PID=$!

# --- 6. Wait for Wayland Socket (The Race Condition Fix) ---
echo "Waiting for Wayland socket..."
TIMEOUT=30
while [ ! -S "$XDG_RUNTIME_DIR/wayland-0" ] && [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]; do
    if [ $TIMEOUT -le 0 ]; then
        echo "Error: Gamescope failed to create Wayland socket!"
        exit 1
    fi
    sleep 1
    ((TIMEOUT--))
done

# Detect which socket was created
if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
else
    export WAYLAND_DISPLAY=wayland-1
fi
echo "Wayland socket found: $WAYLAND_DISPLAY"

# --- 7. Start Sunshine ---
echo "Starting Sunshine..."
# Now that WAYLAND_DISPLAY exists, Sunshine will connect successfully
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export WAYLAND_DISPLAY=$WAYLAND_DISPLAY && sunshine" &

# --- 8. Keep Container Alive ---
wait $GS_PID
