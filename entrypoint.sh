#!/bin/bash
set -e

# --- 0. CLEANUP ---
echo "--- [Boot] Cleaning up ---"
killall -9 sunshine gamescope steam seatd pipewire wireplumber rtkit-daemon 2>/dev/null || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* /run/dbus/pid 2>/dev/null

# --- 1. GLOBAL PERMISSIONS ---
echo "--- [Boot] Setting Permissions ---"
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

# --- 2. RUNTIME ENV ---
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

# --- 3. RUN MODULES ---
export SDL_GAMECONTROLLERCONFIG="050000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
050000004c050000c405000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,"

# Source or execute the modular scripts
/usr/local/bin/scripts/init_system.sh
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" # Set by init_system

/usr/local/bin/scripts/init_audio.sh
/usr/local/bin/scripts/init_proton.sh
/usr/local/bin/scripts/init_sunshine.sh

. /usr/local/bin/scripts/init_system.sh

# Start Watchdog in background
/usr/local/bin/scripts/watchdog.sh &

# --- 4. START GAMESCOPE ---
echo "--- [Boot] Starting Gamescope ---"

# Input Mapping


sudo -E -u steam HOME=/home/steam WLR_LIBINPUT_NO_DEVICES=1 WLR_BACKENDS=headless \
    SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLERCONFIG" \
    UG_MAX_BUFFERS=256 \
    gamescope -e \
    -W "$WIDTH" -H "$HEIGHT" \
    -w "$WIDTH" -h "$HEIGHT" \
    -r "$REFRESH" \
    --force-grab-cursor \
    --hdr-enabled \
    --hdr-itm-enable \
    -- \
    steam -gamepadui -noverifyfiles &

GS_PID=$!

# --- 5. WAIT FOR SOCKETS ---
echo "Waiting for Wayland socket..."
TIMEOUT=90
while [ $TIMEOUT -gt 0 ]; do
    if [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then break; fi
    sleep 1
    ((TIMEOUT--))
done
export WAYLAND_DISPLAY=gamescope-0
chmod 777 $XDG_RUNTIME_DIR/gamescope-0

# --- 6. START SUNSHINE ---
echo "--- [Boot] Starting Sunshine ---"
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
export PULSE_SOURCE="sunshine-stereo.monitor"
export PULSE_SINK="sunshine-stereo"
export XDG_SEAT=seat0 

sunshine &

# --- 7. WAIT ---
wait $GS_PID
