#!/bin/bash
set -e

# --- 1. Setup Directories & Permissions ---
echo "Fixing permissions..."
# Ensure config dirs exist for steam user
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config
chown -R steam:steam /home/steam/.steam
chown -R steam:steam /home/steam/.local

# GPU Access (Global R/W to bypass container groups)
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true

# UINPUT Access (Create node if missing)
if [ ! -e /dev/uinput ]; then
    mknod /dev/uinput c 10 223
fi
chmod 666 /dev/uinput

# Fake TTYs for seatd
if [ ! -e /dev/tty0 ]; then mknod /dev/tty0 c 4 0 && chmod 666 /dev/tty0; fi
if [ ! -e /dev/tty1 ]; then mknod /dev/tty1 c 4 1 && chmod 666 /dev/tty1; fi

# --- 2. Setup Runtime Environment ---
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
echo "Starting seatd..."
seatd & 
export LIBSEAT_BACKEND=seatd
sleep 1
chmod 777 /run/seatd.sock

# --- 4. Start Audio Stack (As Steam) ---
echo "Starting Audio..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# --- 5. Start Gamescope (As Steam) ---
echo "Starting Gamescope..."
# WLR_LIBINPUT_NO_DEVICES=1 prevents crash before Sunshine creates the mouse
sudo -E -u steam HOME=/home/steam WLR_LIBINPUT_NO_DEVICES=1 gamescope \
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
TIMEOUT=90
FOUND_SOCKET=""

while [ $TIMEOUT -gt 0 ]; do
    if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
        FOUND_SOCKET="wayland-0"
        break
    elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
        FOUND_SOCKET="wayland-1"
        break
    elif [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then
        FOUND_SOCKET="gamescope-0"
        break
    fi
    sleep 1
    ((TIMEOUT--))
done

if [ -z "$FOUND_SOCKET" ]; then
    echo "Error: Timed out waiting for Wayland socket!"
    exit 1
fi
export WAYLAND_DISPLAY=$FOUND_SOCKET
echo "Wayland socket found: $WAYLAND_DISPLAY"

# --- 7. Start Sunshine (AS ROOT) ---
echo "Starting Sunshine (Root Mode)..."

# 7.1 Link Configs: Sunshine running as root looks in /root/.config
# We symlink it to the steam user's config mount so your settings persist.
mkdir -p /root/.config
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

# 7.2 Launch
# We run as root to get full /dev/uinput access.
# We point XDG_RUNTIME_DIR and PULSE_SERVER to the 'steam' user's session
# so it can see the display and hear the audio.
export PULSE_SERVER=unix:$XDG_RUNTIME_DIR/pulse/native
export XDG_SEAT=seat0 

# --- 7.5. INPUT PERMISSION WATCHDOG ---
# Sunshine creates /dev/input/event* nodes as ROOT when you connect.
# We must ensure the 'steam' user can read/write them immediately.
echo "Starting Input Watchdog..."
(
    while true; do
        # Force all event devices to be world R/W
        # This covers new devices created by Sunshine
        chmod 666 /dev/input/event* 2>/dev/null
        chmod 666 /dev/input/js* 2>/dev/null
        sleep 2
    done
) &

# Run directly (no su)
sunshine &

# --- 8. Keep Alive ---
wait $GS_PID
