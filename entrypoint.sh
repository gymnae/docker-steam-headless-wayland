#!/bin/bash
set -e

# --- 1. Permissions ---
echo "Fixing permissions..."
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config /home/steam/.steam /home/steam/.local

# Hardware Access (GPU / UINPUT / UHID)
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true
chmod 666 /dev/uinput 2>/dev/null || true
chmod 666 /dev/uhid 2>/dev/null || true        # Required for DS5/DS4 Virtual HID
chmod 666 /dev/hidraw* 2>/dev/null || true     # Required for Gyro/Touchpad

if [ ! -e /dev/uinput ]; then mknod /dev/uinput c 10 223; fi
if [ ! -e /dev/uhid ]; then mknod /dev/uhid c 10 239; fi
chmod 666 /dev/uinput /dev/uhid

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

# --- 3. Start UDEV (Required for Steam Controller Detection) ---
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

# --- 5. Audio Stack (Unified Socket) ---
echo "Starting Audio..."
export PIPEWIRE_LATENCY="1024/48000"
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"

su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# Wait for socket creation
sleep 2
chmod 777 ${XDG_RUNTIME_DIR}/pulse/native 2>/dev/null || true

# --- 6. Gamescope ---
echo "Starting Gamescope..."
# Removed manual SDL mappings so Steam can auto-detect native types
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
# --- 8. Start Sunshine (ROOT MODE with Audio Fix) ---
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

# WATCHDOG (Background)
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

# --- AUDIO PRE-FLIGHT CHECK ---
# We must create the sink BEFORE Sunshine starts so we can bind to it.
echo "Initializing Audio Sink..."

# 1. Define Socket
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
export XDG_SEAT=seat0 

# 2. Create the Sink Manually (as steam user)
su - steam -c "export PULSE_SERVER=$PULSE_SERVER && \
               pactl load-module module-null-sink sink_name=sunshine-stereo sink_properties=device.description=Sunshine_Stereo"

# 3. Set it as Default (as steam user)
su - steam -c "export PULSE_SERVER=$PULSE_SERVER && \
               pactl set-default-sink sunshine-stereo"

# 4. Launch Sunshine with Explicit Source
# The monitor source for a null sink is always 'sink_name.monitor'
export PULSE_SOURCE="sunshine-stereo.monitor"
export PULSE_SINK="sunshine-stereo"

echo "Launching Sunshine attached to $PULSE_SOURCE..."
sunshine &

# --- 9. Keep Alive ---
wait $GS_PID
