#!/bin/bash
set -e

# --- 1. Fix Permissions ---
echo "Fixing permissions..."

# 1.1 Config Directories
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config
chown -R steam:steam /home/steam/.steam
chown -R steam:steam /home/steam/.local

# 1.2 GPU Access
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true

# 1.3 UINPUT ACCESS (The Input Fix)
# We check if the node exists. If not, we make it.
# Then we CHOWN it to steam so there is zero doubt about access.
if [ ! -e /dev/uinput ]; then
    mknod /dev/uinput c 10 223
fi
# Force ownership to steam user
chown steam:steam /dev/uinput
chmod 660 /dev/uinput

# Verify it worked in the logs
ls -l /dev/uinput

# --- 1.5. FAKE TTY ---
if [ ! -e /dev/tty0 ]; then mknod /dev/tty0 c 4 0 && chmod 666 /dev/tty0; fi
if [ ! -e /dev/tty1 ]; then mknod /dev/tty1 c 4 1 && chmod 666 /dev/tty1; fi
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
echo "Starting seatd..."
# REMOVE '-g video'. Run as root to ensure access to Input AND Video devices.
seatd & 
export LIBSEAT_BACKEND=seatd

# Give seatd a moment to create the socket
sleep 1

# Grant 'steam' user access to the seatd socket
chmod 777 /run/seatd.sock

# --- 4. Start Audio Stack ---
echo "Starting Audio..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# --- 5. Start Gamescope (Backgrounded) ---
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

# --- 6. Wait for Wayland Socket (FIXED LOGIC) ---
echo "Waiting for Wayland socket..."
# Increase timeout to 90s for Steam updates
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
    echo "Contents of $XDG_RUNTIME_DIR:"
    ls -la $XDG_RUNTIME_DIR
    exit 1
fi

export WAYLAND_DISPLAY=$FOUND_SOCKET
echo "Wayland socket found: $WAYLAND_DISPLAY"

# --- 7. Start Sunshine ---
echo "Starting Sunshine..."
# ADDED: XDG_SEAT=seat0 so GTK knows where to find input
su - steam -c "export HOME=/home/steam && \
               export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && \
               export WAYLAND_DISPLAY=$WAYLAND_DISPLAY && \
               export XDG_SEAT=seat0 && \
               sunshine" &
# --- 8. Keep Container Alive ---
wait $GS_PID
