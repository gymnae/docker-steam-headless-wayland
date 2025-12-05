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

# --- 3. System Services (DBus + RTKit) ---
echo "Starting System DBus..."
mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork

echo "Starting RTKit..."
if [ -x /usr/lib/rtkit-daemon ]; then
    # FIX: Max (85) must be lower than Our (90)
    /usr/lib/rtkit-daemon --our-realtime-priority=90 --max-realtime-priority=85 &
fi

echo "Starting Session DBus..."
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
su - steam -c "dbus-daemon --session --address=$DBUS_SESSION_BUS_ADDRESS --fork --nopidfile"
sleep 1
export DBUS_SESSION_BUS_ADDRESS

# --- 4. UDEV ---
if [ -x /usr/lib/systemd/systemd-udevd ]; then
    echo "Starting udevd..."
    /usr/lib/systemd/systemd-udevd --daemon
    udevadm trigger
fi

# --- 5. Seatd ---
echo "Starting seatd..."
seatd & 
export LIBSEAT_BACKEND=seatd
sleep 1
chmod 777 /run/seatd.sock

# --- 5. Audio Stack (Robust Start) ---
echo "Starting Audio..."
export PIPEWIRE_LATENCY="512/48000"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"

# 1. Clean locks
rm -rf $XDG_RUNTIME_DIR/pulse $XDG_RUNTIME_DIR/pipewire-0.lock 2>/dev/null
mkdir -p $XDG_RUNTIME_DIR/pulse
chown -R steam:steam $XDG_RUNTIME_DIR/pulse
chmod 700 $XDG_RUNTIME_DIR/pulse

# 2. Start Core
echo "Starting PipeWire Core..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire" &

# WAIT LOOP: Block until pipewire-0 socket exists
echo "Waiting for PipeWire socket..."
TIMEOUT=10
while [ ! -e "$XDG_RUNTIME_DIR/pipewire-0" ]; do
    if [ $TIMEOUT -le 0 ]; then echo "Error: PipeWire socket failed to appear"; exit 1; fi
    sleep 1
    ((TIMEOUT--))
done
echo "PipeWire Core is ready."

# 3. Start WirePlumber (Session Manager)
# Only start this AFTER the socket is confirmed
echo "Starting WirePlumber..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/wireplumber" &

# Give WirePlumber a moment to claim the bus name
sleep 2

# 4. Start PulseAudio Compatibility
echo "Starting PipeWire-Pulse..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &

# WAIT LOOP: Block until pulse native socket exists
echo "Waiting for PulseAudio socket..."
TIMEOUT=10
while [ ! -S "$XDG_RUNTIME_DIR/pulse/native" ]; do
    if [ $TIMEOUT -le 0 ]; then echo "Error: Pulse socket failed to appear"; exit 1; fi
    sleep 1
    ((TIMEOUT--))
done
echo "PulseAudio is ready."

# 5. Grant Access
chmod 777 $XDG_RUNTIME_DIR/pulse/native 2>/dev/null || true

# 6. Create Sink
echo "Configuring PulseAudio Sink..."
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl load-module module-null-sink sink_name=sunshine-stereo rate=48000 sink_properties=device.description=Sunshine_Stereo"

su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl set-default-sink sunshine-stereo"
# --- 6. Proton / Compatibility Tools Fix ---
echo "Linking Proton versions..."

# 1. Ensure the user's Steam directory structure exists
# Steam creates these on first run, but we need them NOW to plant the tools.
mkdir -p /home/steam/.steam/root/compatibilitytools.d
mkdir -p /home/steam/.local/share/Steam/compatibilitytools.d

# 2. Link System Tools (Proton-CachyOS, Proton-GE) to User Steam
# We search the standard system paths and link them into the user's config.
# We use -f (force) to overwrite stale broken links.

# Source A: /usr/share/steam/compatibilitytools.d (Standard Package Location)
if [ -d "/usr/share/steam/compatibilitytools.d" ]; then
    find /usr/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;
fi

# Source B: /usr/local/share/steam/compatibilitytools.d (Alternative Location)
if [ -d "/usr/local/share/steam/compatibilitytools.d" ]; then
    find /usr/local/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;
fi

# 3. Fix Permissions
# Ensure 'steam' user owns the links, otherwise Steam ignores them for security.
chown -R steam:steam /home/steam/.steam/root/compatibilitytools.d

# --- 7. Gamescope ---
echo "Starting Gamescope..."

# 6.1 Define Resolution/Refresh defaults if not set in Docker
# Default to 1440p @ 60Hz if variables are missing
WIDTH=${DISPLAY_WIDTH:-2560}
HEIGHT=${DISPLAY_HEIGHT:-1440}
REFRESH=${DISPLAY_REFRESH:-60}

echo "Configuring Display: ${WIDTH}x${HEIGHT} @ ${REFRESH}Hz"

# 6.3 Launch Gamescope with Variables
# -W/-H: Internal Game Resolution
# -w/-h: Output Window Resolution (We match them for 1:1 pixel mapping)
# -r: Refresh Rate
sudo -E -u steam HOME=/home/steam WLR_LIBINPUT_NO_DEVICES=1 \
    gamescope \
    -W "$WIDTH" -H "$HEIGHT" \
    -w "$WIDTH" -h "$HEIGHT" \
    -r "$REFRESH" \
    -F fsr \
    --force-grab-cursor \
    --steam \
    -- \
    steam -gamepadui -noverifyfiles &

GS_PID=$!

# --- 8. Wait for Socket ---
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

# --- 9. Start Sunshine (ROOT + TCP) ---
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

# --- 10. Keep Alive ---
wait $GS_PID
