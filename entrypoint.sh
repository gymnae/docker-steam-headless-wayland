#!/bin/bash
set -e

# --- 1. Global Permission Fixes ---
echo "Fixing permissions..."
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config
chown -R steam:steam /home/steam/.steam
chown -R steam:steam /home/steam/.local

# 1.1 GPU Access
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true

# 1.2 UINPUT ACCESS (Critical)
# We make the device node world-writable so 'steam' user can open it.
if [ ! -e /dev/uinput ]; then
    mknod /dev/uinput c 10 223
fi
chmod 666 /dev/uinput

# 1.3 Fake TTYs
if [ ! -e /dev/tty0 ]; then mknod /dev/tty0 c 4 0 && chmod 666 /dev/tty0; fi
if [ ! -e /dev/tty1 ]; then mknod /dev/tty1 c 4 1 && chmod 666 /dev/tty1; fi

# --- 2. Runtime Environment ---
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

# Start DBus
mkdir -p /run/dbus
dbus-daemon --system --fork

echo "Starting Session DBus..."
DBUS_ENV=$(su - steam -c "dbus-launch --sh-syntax")
eval "$DBUS_ENV"
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SYSTEM_BUS_ADDRESS

# --- 3. Start Hardware Daemon ---
echo "Starting seatd..."
seatd & 
export LIBSEAT_BACKEND=seatd
sleep 1
chmod 777 /run/seatd.sock

# --- 4. Start Audio Stack ---
echo "Starting Audio..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# --- 5. Start Gamescope ---
echo "Starting Gamescope..."
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
    if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then FOUND_SOCKET="wayland-0"; break; fi
    if [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then FOUND_SOCKET="wayland-1"; break; fi
    if [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then FOUND_SOCKET="gamescope-0"; break; fi
    sleep 1
    ((TIMEOUT--))
done
if [ -z "$FOUND_SOCKET" ]; then echo "Error: Wayland socket missing"; exit 1; fi
export WAYLAND_DISPLAY=$FOUND_SOCKET
echo "Wayland socket found: $WAYLAND_DISPLAY"

# --- 7. Start Sunshine (AS STEAM) ---
echo "Starting Sunshine..."

# 7.1 Input Watchdog (Runs as Root)
# Continually ensures permissions stay open for new devices
(
    while true; do
        chmod 666 /dev/input/event* 2>/dev/null
        chmod 666 /dev/input/js* 2>/dev/null
        sleep 2
    done
) &

# 7.2 Audio Fixer (Runs as Steam)
# Waits for Sunshine sink to appear, then sets it as default
su - steam -c "
    export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
    sleep 10
    # Find the ID of the Sunshine sink (more robust than name)
    SINK_ID=\$(wpctl status | grep 'Sunshine' | awk '{print \$2}' | tr -d '.')
    if [ ! -z \"\$SINK_ID\" ]; then
        echo \"Setting Default Sink to ID: \$SINK_ID\"
        wpctl set-default \$SINK_ID
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
    else
        echo \"Warning: Sunshine Audio Sink not found!\"
    fi
" &

# 7.3 Launch Sunshine (As Steam User)
# This fixes the GDK Seat errors because User ID matches Gamescope User ID.
# We explicitly set XDG_SEAT so it knows where to attach.
su - steam -c "export HOME=/home/steam && \
               export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && \
               export WAYLAND_DISPLAY=$WAYLAND_DISPLAY && \
               export XDG_SEAT=seat0 && \
               sunshine" &

# --- 8. Keep Alive ---
wait $GS_PID
