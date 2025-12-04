#!/bin/bash
set -e

# --- 1. Fix Permissions ---
echo "Fixing permissions..."
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config
chown -R steam:steam /home/steam/.steam
chown -R steam:steam /home/steam/.local

# GPU & Input Access
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true
chmod 666 /dev/uinput 2>/dev/null || true

# --- 1.5. FAKE TTY (Crucial for seatd) ---
# seatd needs a VT to manage. We create fake TTY nodes to satisfy it.
if [ ! -e /dev/tty0 ]; then
    mknod /dev/tty0 c 4 0
    chmod 666 /dev/tty0
fi
if [ ! -e /dev/tty1 ]; then
    mknod /dev/tty1 c 4 1
    chmod 666 /dev/tty1
fi

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

# --- 3. Start Seat Daemon ---
# -g video: Allow video group (steam) to connect
# We do NOT use -n (socket activation) as it caused errors previously
echo "Starting seatd..."
seatd -g video &
export LIBSEAT_BACKEND=seatd

# --- 4. Start Audio Stack ---
echo "Starting Audio..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# --- 5. Start Gamescope (Backgrounded) ---
echo "Starting Gamescope..."
# We run as 'steam' but keep our environment variables
# HOME=/home/steam prevents the "Permission denied /root/..." error
sudo -E -u steam HOME=/home/steam gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --force-grab-cursor \
    -- \
    steam -gamepadui -tenfoot &

GS_PID=$!

# --- 6. Wait for Wayland Socket ---
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

# Detect socket
if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
else
    export WAYLAND_DISPLAY=wayland-1
fi
echo "Wayland socket found: $WAYLAND_DISPLAY"

# --- 7. Start Sunshine ---
echo "Starting Sunshine..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export WAYLAND_DISPLAY=$WAYLAND_DISPLAY && sunshine" &

# --- 8. Keep Container Alive ---
wait $GS_PID
