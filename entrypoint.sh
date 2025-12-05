#!/bin/bash
set -e

# --- 0. CLEANUP ---
echo "Cleaning up..."
killall -9 sunshine gamescope steam seatd pipewire wireplumber 2>/dev/null || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* 2>/dev/null

# --- 1. Permissions ---
echo "Fixing permissions..."
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config /home/steam/.steam /home/steam/.local

chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true
chmod 666 /dev/uinput 2>/dev/null || true
chmod 666 /dev/hidraw* 2>/dev/null || true
chmod 666 /dev/uhid 2>/dev/null || true

if [ ! -e /dev/uinput ]; then mknod /dev/uinput c 10 223; fi
chmod 666 /dev/uinput

if [ ! -e /dev/tty0 ]; then mknod /dev/tty0 c 4 0 && chmod 666 /dev/tty0; fi
if [ ! -e /dev/tty1 ]; then mknod /dev/tty1 c 4 1 && chmod 666 /dev/tty1; fi

# --- 2. Runtime ---
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

mkdir -p /run/dbus
dbus-daemon --system --fork

echo "Starting Session DBus..."
# Run DBus as steam
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
su - steam -c "dbus-daemon --session --address=$DBUS_SESSION_BUS_ADDRESS --fork --nopidfile"
sleep 1
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

# --- 5. Audio Stack (TCP MODE) ---
echo "Starting Audio..."
export PIPEWIRE_LATENCY="1024/48000"

su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

sleep 3

# ENABLE TCP & CREATE SINK
echo "Configuring PulseAudio..."
# Load TCP module
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1"

# Create Sink
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl load-module module-null-sink sink_name=sunshine-stereo sink_properties=device.description=Sunshine_Stereo"

# Set Default (We do this here so Sunshine doesn't have to)
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl set-default-sink sunshine-stereo"

# --- 6. Gamescope ---
echo "Starting Gamescope..."
sudo -E -u steam HOME=/home/steam WLR_LIBINPUT_NO_DEVICES=1 \
    SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLERCONFIG" \
    gamescope \
    -W 2560 -H 1440 \
    -w 2560 -h 1440 \
    -r 60 \
    -F fsr \
    --force-grab-cursor \
    -- \
    steam -gamepadui -pipewire-dmabuf &

GS_PID=$!

# --- 7. Wait for Socket ---
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

# --- 8. Start Sunshine (ROOT + TCP) ---
echo "Starting Sunshine (Root Mode)..."
mkdir -p /root/.config
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

# CONFIG: REMOVED 'audio_sink' to prevent permission error
mkdir -p /home/steam/.config/sunshine
cat > /home/steam/.config/sunshine/sunshine.conf <<EOF
[general]
address = 0.0.0.0
upnp = disabled
gamepad = auto
[video]
capture = kms
encoder = nvenc
EOF
chown steam:steam /home/steam/.config/sunshine/sunshine.conf

# Watchdog
(
    LAST_COUNT=0
    while true; do
        NEW_COUNT=$(ls -1 /dev/input | wc -l)
        if [ "$NEW_COUNT" != "$LAST_COUNT" ]; then
            udevadm trigger --action=change --subsystem-match=input
            LAST_COUNT=$NEW_COUNT
        fi
        chmod 666 /dev/input/event* 2>/dev/null
        chmod 666 /dev/input/js* 2>/dev/null
        chmod 666 /dev/hidraw* 2>/dev/null
        chmod 666 /dev/uhid 2>/dev/null
        sleep 5
    done
) &

# Force TCP Audio & Source
export PULSE_SERVER="tcp:127.0.0.1"
export PULSE_SOURCE="sunshine-stereo.monitor"
export PULSE_SINK="sunshine-stereo"
export XDG_SEAT=seat0 

sunshine &

# --- 9. Keep Alive ---
wait $GS_PID
