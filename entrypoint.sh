#!/bin/bash
set -e

# --- 0. SIGNAL TRAPPING (Graceful Shutdown) ---
# If Docker sends SIGTERM, we kill everything and exit the loop.
trap "echo 'Stopping container...'; killall -9 sunshine gamescope steam seatd pipewire wireplumber udevd 2>/dev/null; exit 0" SIGTERM SIGINT

# --- 1. GLOBAL CLEANUP ---
echo "Cleaning up zombie processes..."
killall -9 sunshine gamescope steam seatd pipewire wireplumber rtkit-daemon 2>/dev/null || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* /run/dbus/pid 2>/dev/null

# --- 2. PERMISSIONS ---
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

# --- 3. RUNTIME ENVIRONMENT ---
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

mkdir -p /run/dbus
dbus-daemon --system --fork

echo "Starting Session DBus..."
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
su - steam -c "dbus-daemon --session --address=$DBUS_SESSION_BUS_ADDRESS --fork --nopidfile"
sleep 1
export DBUS_SESSION_BUS_ADDRESS

# --- 4. GLOBAL SERVICES (Start Once) ---

# UDEV
if [ -x /usr/lib/systemd/systemd-udevd ]; then
    echo "Starting udevd..."
    /usr/lib/systemd/systemd-udevd --daemon
    udevadm trigger
fi

# SEATD
echo "Starting seatd..."
seatd & 
export LIBSEAT_BACKEND=seatd
sleep 1
chmod 777 /run/seatd.sock

# AUDIO STACK (Socket Mode)
echo "Starting Audio..."
export PIPEWIRE_LATENCY="512/48000"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"

su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export DBUS_SYSTEM_BUS_ADDRESS='$DBUS_SYSTEM_BUS_ADDRESS' && /usr/bin/pipewire" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export DBUS_SYSTEM_BUS_ADDRESS='$DBUS_SYSTEM_BUS_ADDRESS' && /usr/bin/pipewire-pulse" &
su - steam -c "export HOME=/home/steam && export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' && export DBUS_SYSTEM_BUS_ADDRESS='$DBUS_SYSTEM_BUS_ADDRESS' && /usr/bin/wireplumber" &

sleep 2

# AUDIO SINK CONFIG
echo "Configuring PulseAudio Sink..."
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl load-module module-null-sink sink_name=sunshine-stereo rate=48000 sink_properties=device.description=Sunshine_Stereo"

su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl set-default-sink sunshine-stereo"

chmod 777 $XDG_RUNTIME_DIR/pulse/native 2>/dev/null || true

# PROTON LINKING
echo "Linking Proton versions..."
mkdir -p /home/steam/.steam/root/compatibilitytools.d
if [ -d "/usr/share/steam/compatibilitytools.d" ]; then
    find /usr/share/steam/compatibilitytools.d/ -maxdepth 1 -mindepth 1 -type d \
    -exec ln -sfn {} /home/steam/.steam/root/compatibilitytools.d/ \;
fi
chown -R steam:steam /home/steam/.steam/root/compatibilitytools.d

# CONFIG GENERATION
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
        
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && wpctl set-default sink-sunshine-stereo" 2>/dev/null
        su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0" 2>/dev/null
        
        sleep 5
    done
) &


# ==============================================================================
# --- 5. THE RESURRECTION LOOP (Session Management) ---
# ==============================================================================
# This loop keeps Steam/Gamescope alive. If you "Exit Steam", it simply restarts.
# To stop the container, use 'docker stop' (handled by the trap above).

export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
export PULSE_SOURCE="sunshine-stereo.monitor"
export PULSE_SINK="sunshine-stereo"
export XDG_SEAT=seat0 

# DUALSENSE MAPPING
export SDL_GAMECONTROLLERCONFIG="050000004c050000c405000000850000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,"

while true; do
    echo "--- Starting Session ---"
    
    # 5.1 Start Gamescope
    sudo -E -u steam HOME=/home/steam WLR_LIBINPUT_NO_DEVICES=1 \
        SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLERCONFIG" \
        UG_MAX_BUFFERS=256 \
        gamescope \
        -W "$WIDTH" -H "$HEIGHT" \
        -w "$WIDTH" -h "$HEIGHT" \
        -r "$REFRESH" \
        --force-grab-cursor \
        --steam \
        -- \
        steam -gamepadui -noverifyfiles &
    
    GS_PID=$!
    
    # 5.2 Wait for Wayland Socket (Needed for Sunshine)
    TIMEOUT=20
    while [ ! -S "$XDG_RUNTIME_DIR/gamescope-0" ] && [ $TIMEOUT -gt 0 ]; do
        sleep 0.5
        ((TIMEOUT--))
    done
    export WAYLAND_DISPLAY=gamescope-0
    chmod 777 $XDG_RUNTIME_DIR/gamescope-0 2>/dev/null || true
    
    # 5.3 Start Sunshine
    # We must restart Sunshine every time Gamescope restarts because the Wayland socket changes/dies
    if [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then
        echo "Starting Sunshine..."
        sunshine &
        SUNSHINE_PID=$!
    fi
    
    # 5.4 Wait for Gamescope to Exit (Blocking)
    wait $GS_PID
    
    # 5.5 Cleanup before restart
    echo "Session ended (Steam/Gamescope exited). Restarting in 3 seconds..."
    kill $SUNSHINE_PID 2>/dev/null || true
    rm -f $XDG_RUNTIME_DIR/gamescope-0
    sleep 3
done
