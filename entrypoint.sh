#!/bin/bash
set -e

# --- 1. Permissions ---
echo "Fixing permissions..."
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config /home/steam/.steam /home/steam/.local

# GPU/Input/HID Access
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true
chmod 666 /dev/uinput 2>/dev/null || true
chmod 666 /dev/hidraw* 2>/dev/null || true

if [ ! -e /dev/uinput ]; then mknod /dev/uinput c 10 223; fi
chmod 666 /dev/uinput

# Fake TTYs
if [ ! -e /dev/tty0 ]; then mknod /dev/tty0 c 4 0 && chmod 666 /dev/tty0; fi
if [ ! -e /dev/tty1 ]; then mknod /dev/tty1 c 4 1 && chmod 666 /dev/tty1; fi

# --- 2. Runtime Environment ---
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

mkdir -p /run/dbus
dbus-daemon --system --fork

echo "Starting Session DBus..."
DBUS_ENV=$(su - steam -c "dbus-launch --sh-syntax")
eval "$DBUS_ENV"
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SYSTEM_BUS_ADDRESS

# --- 3. Start UDEV (CRITICAL) ---
if [ -x /usr/lib/systemd/systemd-udevd ]; then
    echo "Starting udevd..."
    /usr/lib/systemd/systemd-udevd --daemon
    udevadm trigger
fi

# --- 4. Seatd ---
echo "Starting seatd..."
seatd & 
export LIBSEAT_BACKEND=seatd
sleep 1
chmod 777 /run/seatd.sock

# --- 5. Audio Stack ---
echo "Starting Audio..."
export PIPEWIRE_LATENCY="1024/48000"
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# --- 6. Gamescope ---
echo "Starting Gamescope..."

# FIX: Disable EI (Input Emulation) to prevent crashes
# We also add --headless explicitly to be safe, though embedded usually implies it.
sudo -E -u steam HOME=/home/steam WLR_LIBINPUT_NO_DEVICES=1 gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --disable-xwayland-ei \
    --force-grab-cursor \
    -- \
    steam -gamepadui -tenfoot &

GS_PID=$!

# --- 7. Wait for Wayland Socket ---
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

# --- 8. Start Sunshine (STEAM USER MODE) ---
echo "Starting Sunshine..."

# Smart Watchdog (Runs as Root)
(
    LAST_COUNT=0
    while true; do
        # Trigger udev when devices change (Fixes Input)
        NEW_COUNT=$(ls -1 /dev/input | wc -l)
        if [ "$NEW_COUNT" != "$LAST_COUNT" ]; then
            udevadm trigger --action=change --subsystem-match=input
            LAST_COUNT=$NEW_COUNT
        fi
        
        # Keep permissions open
        chmod 666 /dev/input/event* 2>/dev/null
        chmod 666 /dev/input/js* 2>/dev/null
        chmod 666 /dev/hidraw* 2>/dev/null
        
        # Fix Audio
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && wpctl set-default sink-sunshine-stereo" 2>/dev/null
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0" 2>/dev/null
        
        sleep 5
    done
) &

# LAUNCH SUNSHINE AS STEAM
# This prevents the GDK crash. We rely on the Dockerfile 'setcap' to allow uinput access.
export PULSE_SERVER=unix:$XDG_RUNTIME_DIR/pulse/native
export XDG_SEAT=seat0 

su - steam -c "export HOME=/home/steam && \
               export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && \
               export WAYLAND_DISPLAY=$WAYLAND_DISPLAY && \
               export PULSE_SERVER=unix:$XDG_RUNTIME_DIR/pulse/native && \
               export XDG_SEAT=seat0 && \
               sunshine" &

# --- 9. Verification & Keep Alive ---
sleep 5
# Check if Sunshine is alive using 'ps' or 'ss' (since netstat might be missing)
echo "Checking Sunshine status..."
if ps aux | grep -v grep | grep sunshine > /dev/null; then
    echo "Sunshine is RUNNING."
else
    echo "Sunshine CRASHED immediately. Checking logs..."
fi

wait $GS_PID
