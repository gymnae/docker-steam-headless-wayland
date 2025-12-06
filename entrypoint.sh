#!/bin/bash
set -e

# --- 0. SIGNAL TRAPPING ---
trap "echo 'Stopping container...'; killall -15 sunshine gamescope steam seatd pipewire wireplumber udevd 2>/dev/null; exit 0" SIGTERM SIGINT

# --- 1. GLOBAL SETUP ---
echo "Initializing Container..."

# Create Dirs
mkdir -p /home/steam/.config/sunshine /home/steam/.steam /home/steam/.local/state

# Fix Permissions (Recursive)
# We force ownership to steam:steam so the container can read the bind mount
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

# Runtime
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

# DBus
mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork

echo "Starting Session DBus..."
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
su - steam -c "dbus-daemon --session --address=$DBUS_SESSION_BUS_ADDRESS --fork --nopidfile"
sleep 1
export DBUS_SESSION_BUS_ADDRESS

# Udev
if [ -x /usr/lib/systemd/systemd-udevd ]; then
    echo "Starting udevd..."
    /usr/lib/systemd/systemd-udevd --daemon
    udevadm trigger
fi

# Audio Stack
echo "Starting Audio..."
export PIPEWIRE_LATENCY="512/48000"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"

su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export DBUS_SYSTEM_BUS_ADDRESS='$DBUS_SYSTEM_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export DBUS_SYSTEM_BUS_ADDRESS='$DBUS_SYSTEM_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export DBUS_SYSTEM_BUS_ADDRESS='$DBUS_SYSTEM_BUS_ADDRESS' && /usr/bin/wireplumber" &

sleep 2

# Audio Sink
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl load-module module-null-sink sink_name=sunshine-stereo rate=48000 sink_properties=device.description=Sunshine_Stereo"
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl set-default-sink sunshine-stereo"
chmod 777 $XDG_RUNTIME_DIR/pulse/native 2>/dev/null || true

# Proton Links
mkdir -p /home/steam/.steam/root/compatibilitytools.d
if [ -d "/usr/share/steam/compatibilitytools.d" ]; then
    find /usr/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;
fi
chown -R steam:steam /home/steam/.steam/root/compatibilitytools.d

# --- CONFIG PERSISTENCE CHECK ---
CONF_DIR="/home/steam/.config/sunshine"
CONF_FILE="$CONF_DIR/sunshine.conf"

echo "Checking Sunshine Config at: $CONF_FILE"

if [ -s "$CONF_FILE" ]; then
    echo "✅ Existing config found ($(stat -c%s "$CONF_FILE") bytes). Keeping it."
else
    echo "⚠️  Config missing or empty. Writing default..."
    mkdir -p "$CONF_DIR"
    cat > "$CONF_FILE" <<EOF
[general]
address = 0.0.0.0
upnp = disabled
gamepad = auto
[video]
capture = kms
encoder = nvenc
EOF
fi

# Ensure permissions are correct again after potential write
chown -R steam:steam "$CONF_DIR"

# Link for Root (Sunshine runs as root)
rm -rf /root/.config/sunshine
mkdir -p /root/.config
# We link the FOLDER, not the file, so Sunshine sees apps.json too
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

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
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && wpctl set-default sink-sunshine-stereo" 2>/dev/null
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0" 2>/dev/null
        sleep 5
    done
) &

# ==============================================================================
# --- SESSION LOOP ---
# ==============================================================================

# DUALSENSE MAPPING
export SDL_GAMECONTROLLERCONFIG="050000004c050000c405000000850000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
050000004c050000c405000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,"

# Socket Variables
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
export PULSE_SOURCE="sunshine-stereo.monitor"
export PULSE_SINK="sunshine-stereo"
export XDG_SEAT=seat0 

while true; do
    echo "--- Starting Session ---"

    # 1. Cleanup Zombies (PID File Fix)
    # We must remove the steam.pid file or Steam thinks it's still running
    rm -f /home/steam/.steam/steam.pid 2>/dev/null
    rm -f /home/steam/.steam/root/steam.pid 2>/dev/null
    
    pkill -9 -u steam steam || true
    pkill -9 -u steam steamwebhelper || true
    rm -f /run/seatd.sock

    # 2. Restart Seatd
    # Kill old instance if it exists
    killall seatd 2>/dev/null || true
    seatd &
    SEATD_PID=$!
    export LIBSEAT_BACKEND=seatd
    sleep 1
    chmod 777 /run/seatd.sock

    # 3. Start Gamescope
    sudo -E -u steam HOME=/home/steam WLR_LIBINPUT_NO_DEVICES=1 \
        SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLERCONFIG" \
        UG_MAX_BUFFERS=256 \
        gamescope \
        -W "$WIDTH" -H "$HEIGHT" \
        -w "$WIDTH" -h "$HEIGHT" \
        -r "$REFRESH" \
        --steam \
        --force-grab-cursor \
        -- \
        steam -gamepadui -noverifyfiles &
    
    GS_PID=$!
    
    # 4. Wait for Socket
    TIMEOUT=30
    while [ ! -S "$XDG_RUNTIME_DIR/gamescope-0" ] && [ $TIMEOUT -gt 0 ]; do
        sleep 0.5
        ((TIMEOUT--))
    done
    export WAYLAND_DISPLAY=gamescope-0
    chmod 777 $XDG_RUNTIME_DIR/gamescope-0 2>/dev/null || true
    
    # 5. Start Sunshine
    if [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then
        echo "Starting Sunshine..."
        sunshine &
        SUNSHINE_PID=$!
    fi
    
    # 6. Monitor Steam
    sleep 15
    echo "Monitoring Steam process..."
    while kill -0 $GS_PID 2>/dev/null; do
        if ! pgrep -u steam -x steam > /dev/null && ! pgrep -u steam -x steam-runtime > /dev/null; then
             echo "Steam process disappeared. Resetting session..."
             break
        fi
        sleep 3
    done
    
    # 7. Teardown
    echo "Session ended. Cleaning up..."
    kill $GS_PID 2>/dev/null || true
    kill $SUNSHINE_PID 2>/dev/null || true
    
    sleep 3
done
