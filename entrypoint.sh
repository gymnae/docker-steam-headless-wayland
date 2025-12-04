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

# --- 2. Runtime Environment & DBus ---
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

# Start System DBus (Root)
mkdir -p /run/dbus
dbus-daemon --system --fork

# Start Session DBus (AS STEAM USER)
# This is crucial. PipeWire and Gamescope run as steam, so the bus must belong to steam.
echo "Starting Session DBus as steam..."
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# We use 'su' to start the daemon as the user
su - steam -c "dbus-daemon --session --address=$DBUS_SESSION_BUS_ADDRESS --fork --nopidfile"

# Give it a moment to start
sleep 1

# Export for Root processes (like Sunshine) to see it
export DBUS_SESSION_BUS_ADDRESS

# --- 3. Start UDEV ---
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
# Note: We don't need to pass DBUS address explicitly anymore because the user session owns it
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# --- 6. Gamescope ---
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
chmod 777 $XDG_RUNTIME_DIR/$FOUND_SOCKET

# --- 8. Start Sunshine (ROOT MODE) ---
echo "Starting Sunshine (Root Mode)..."
mkdir -p /root/.config
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

# Ensure sunshine.conf allows "auto" gamepads
mkdir -p /home/steam/.config/sunshine
cat > /home/steam/.config/sunshine/sunshine.conf <<EOF
[general]
address = 0.0.0.0
port = 47990
upnp = disabled
gamepad = auto
[video]
capture = kms
encoder = nvenc
[audio]
audio_sink = pulse
EOF
chown steam:steam /home/steam/.config/sunshine/sunshine.conf

# PulseAudio Cookie Fix
if [ -f /home/steam/.config/pulse/cookie ]; then
    mkdir -p /root/.config/pulse
    cp /home/steam/.config/pulse/cookie /root/.config/pulse/cookie
fi

# SMART WATCHDOG (Gentle Version)
(
    # Initial Trigger to populate DB
    udevadm trigger --action=add
    udevadm settle
    
    LAST_COUNT=$(ls -1 /dev/input | wc -l)
    
    while true; do
        CURRENT_COUNT=$(ls -1 /dev/input | wc -l)
        
        # Only trigger if device count CHANGES
        if [ "$CURRENT_COUNT" != "$LAST_COUNT" ]; then
            echo "New input devices detected! Triggering udev..."
            udevadm trigger --action=change --subsystem-match=input
            LAST_COUNT=$CURRENT_COUNT
        fi

        # Always ensure permissions (Cheap operation)
        chmod 666 /dev/input/event* 2>/dev/null
        chmod 666 /dev/input/js* 2>/dev/null
        chmod 666 /dev/hidraw* 2>/dev/null

        # Keep Audio Alive (Only if it died)
        if ! pgrep -u steam wireplumber > /dev/null; then
             su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &
        fi
        
        # Force Sink Default (Once every 10s is enough)
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && wpctl set-default sink-sunshine-stereo" 2>/dev/null
        
        sleep 5
    done
) &

export PULSE_SERVER=unix:$XDG_RUNTIME_DIR/pulse/native
export XDG_SEAT=seat0 
sunshine &

# --- 9. Keep Alive ---
wait $GS_PID
