#!/bin/bash
set -e

# --- 1. Permissions ---
echo "Fixing permissions..."
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config /home/steam/.steam /home/steam/.local

# GPU/Input Access
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true
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

# --- 3. Seatd ---
echo "Starting seatd..."
seatd & 
export LIBSEAT_BACKEND=seatd
sleep 1
chmod 777 /run/seatd.sock

# --- 4. Audio Stack ---
echo "Starting Audio..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# --- 5. Gamescope ---
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

# ALLOW ROOT ACCESS TO SOCKET
chmod 777 $XDG_RUNTIME_DIR/$FOUND_SOCKET

# --- 7. Start Sunshine (ROOT MODE) ---
echo "Starting Sunshine (Root Mode)..."
mkdir -p /root/.config
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

# Copy PulseAudio cookie for Root access
if [ -f /home/steam/.config/pulse/cookie ]; then
    mkdir -p /root/.config/pulse
    cp /home/steam/.config/pulse/cookie /root/.config/pulse/cookie
fi

# --- WATCHDOG: FIX INPUT & AUDIO ---
(
    while true; do
        # 1. FORCE UDEV TRIGGER (This fixes empty libinput list!)
        # Tells the kernel to announce the devices again so userspace sees them.
        udevadm trigger --action=change --subsystem-match=input
        
        # 2. Force permissions on devices
        chmod 666 /dev/input/event* 2>/dev/null
        chmod 666 /dev/input/js* 2>/dev/null
        
        # 3. Keep-Alive for Audio
        # If WirePlumber dies (common in headless), restart it
        if ! pgrep -u steam wireplumber > /dev/null; then
            echo "Restarting WirePlumber..."
            su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &
        fi
        
        sleep 5
    done
) &

# Launch Sunshine
export PULSE_SERVER=unix:$XDG_RUNTIME_DIR/pulse/native
export XDG_SEAT=seat0 
sunshine &

# --- 8. Keep Alive ---
wait $GS_PID
