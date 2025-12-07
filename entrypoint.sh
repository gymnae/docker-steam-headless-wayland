#!/bin/bash
set -e

# --- 0. CLEANUP ---
echo "Cleaning up..."
killall -9 sunshine gamescope steam seatd pipewire wireplumber rtkit-daemon 2>/dev/null || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* /run/dbus/pid 2>/dev/null

# FIX: Wipe WirePlumber state to prevent crash loops on restart
rm -rf /home/steam/.local/state/wireplumber

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

# --- 2. Runtime Environment ---
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

# FIX: Generate Machine ID for DBus stability
if [ ! -f /etc/machine-id ]; then
    dbus-uuidgen > /etc/machine-id
fi
mkdir -p /var/lib/dbus
dbus-uuidgen > /var/lib/dbus/machine-id

mkdir -p /run/dbus
dbus-daemon --system --fork

echo "Starting Session DBus..."
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

# --- 5. Audio Stack (Socket Mode - Fixed) ---
echo "Starting Audio..."
export PIPEWIRE_LATENCY=128/48000
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"
export PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR

# 1. Clean locks
rm -rf $XDG_RUNTIME_DIR/pulse $XDG_RUNTIME_DIR/pipewire-0.lock 2>/dev/null
mkdir -p $XDG_RUNTIME_DIR/pulse
chown -R steam:steam $XDG_RUNTIME_DIR/pulse
chmod 700 $XDG_RUNTIME_DIR/pulse

# 2. Start Core
echo "Starting PipeWire Core..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export DBUS_SYSTEM_BUS_ADDRESS='$DBUS_SYSTEM_BUS_ADDRESS' && /usr/bin/pipewire" &

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
# FIX: Removed DBUS_SYSTEM_BUS_ADDRESS from WirePlumber env to prevent RTKit confusion crashing the loop
echo "Starting WirePlumber..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR && /usr/bin/wireplumber" &

# Give WirePlumber a moment
sleep 2
# 4. Start PulseAudio Compatibility
echo "Starting PipeWire-Pulse..."
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export DBUS_SYSTEM_BUS_ADDRESS='$DBUS_SYSTEM_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &

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
               pactl load-module module-null-sink sink_name=sunshine-stereo sink_properties=device.description=Sunshine_Stereo"

su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl set-default-sink sunshine-stereo"

# --- 6. Proton Linking ---
echo "Linking Proton versions..."
mkdir -p /home/steam/.steam/root/compatibilitytools.d
if [ -d "/usr/share/steam/compatibilitytools.d" ]; then
    find /usr/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;
fi
chown -R steam:steam /home/steam/.steam/root/compatibilitytools.d

# --- 7. Gamescope ---
echo "Starting Gamescope..."
echo "Starting Gamescope..."

# DUALSENSE EDGE MAPPING FIX (Comprehensive)
# We provide mappings for:
# 1. Bluetooth + Version 8111 (Exact match from your logs)
# 2. Bluetooth + Version 0 (Common virtual fallback)
# 3. USB + Version 8111 (If SDL sees it as USB)
# 4. USB + Version 0 (Generic fallback)
export SDL_GAMECONTROLLERCONFIG="050000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,"

sudo -E -u steam HOME=/home/steam WLR_LIBINPUT_NO_DEVICES=1 WLR_BACKENDS=headless \
    SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLERCONFIG" \
    UG_MAX_BUFFERS=256 \
    gamescope -e \
    --headless \
    -W "$WIDTH" -H "$HEIGHT" \
    -w "$WIDTH" -h "$HEIGHT" \
    -r "$REFRESH" \
    --force-grab-cursor \
    --hdr-enabled \
    --hdr-debug-force-output \
    --hdr-itm-enable \
    --expose-wayland \
    -- \
    steam -gamepadui -noverifyfiles &

GS_PID=$!

# --- 8. Wait for Wayland Socket ---
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

# --- 9. Start Sunshine (ROOT) ---
echo "Starting Sunshine (Root Mode)..."
mkdir -p /root/.config
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

# Config
mkdir -p /home/steam/.config/sunshine
cat > /home/steam/.config/sunshine/sunshine.conf <<EOF
[general]
address = 0.0.0.0
upnp = disabled
gamepad = auto
[video]
capture = kms
encoder = nvenc
hevc_mode = 1
EOF
chown steam:steam /home/steam/.config/sunshine/sunshine.conf

# Pulse Cookie Copy
if [ -f /home/steam/.config/pulse/cookie ]; then
    mkdir -p /root/.config/pulse
    cp /home/steam/.config/pulse/cookie /root/.config/pulse/cookie
fi

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
        
        # Audio Keep-Alive
        # Re-assert default sink if it changes
        if su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl get-default-sink" | grep -qv "sunshine-stereo"; then
             su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl set-default-sink sunshine-stereo" 2>/dev/null
        fi
        
        sleep 5
    done
) &

# SOCKET AUDIO CONNECTION
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
export PULSE_SOURCE="sunshine-stereo.monitor"
export PULSE_SINK="sunshine-stereo"
export XDG_SEAT=seat0 

sunshine &

# --- 10. Keep Alive ---
wait $GS_PID
