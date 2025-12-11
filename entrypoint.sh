#!/bin/bash
set -e

# --- 0. CLEANUP ---
echo "--- [Boot] Cleaning up ---"
killall -9 sunshine gamescope steam seatd pipewire wireplumber rtkit-daemon 2>/dev/null || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* /run/dbus/pid 2>/dev/null

# --- 1. RUNTIME ENV & PERMISSIONS ---
echo "--- [Boot] Setting Environment & Permissions ---"

# Set defaults
WIDTH=${WIDTH:-1920}
HEIGHT=${HEIGHT:-1080}
REFRESH=${REFRESH:-60}

# Set vars first
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
chown steam:steam $XDG_RUNTIME_DIR

# Fix device permissions
chmod 666 /dev/dri/card0 2>/dev/null || true
chmod 666 /dev/dri/renderD* 2>/dev/null || true
chmod 666 /dev/uinput 2>/dev/null || true
chmod 666 /dev/hidraw* 2>/dev/null || true
chmod 666 /dev/uhid 2>/dev/null || true

if [ ! -e /dev/uinput ]; then mknod /dev/uinput c 10 223; fi
chmod 666 /dev/uinput
if [ ! -e /dev/tty0 ]; then mknod /dev/tty0 c 4 0 && chmod 666 /dev/tty0; fi
if [ ! -e /dev/tty1 ]; then mknod /dev/tty1 c 4 1 && chmod 666 /dev/tty1; fi

# Fix Steam directories
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config /home/steam/.steam /home/steam/.local

# --- 2. CREATE STEAM WRAPPER ---
# This wrapper is CRITICAL. It hides the Steam flags from Gamescope.
cat <<'EOF' > /usr/local/bin/start_steam.sh
#!/bin/bash
export SDL_GAMECONTROLLERCONFIG="050000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
050000004c050000c405000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,"


exec steam -noverifyfiles -gamepadui
EOF
chmod +x /usr/local/bin/start_steam.sh
chown steam:steam /usr/local/bin/start_steam.sh

# --- 3. RUN MODULES ---
if [ -f /usr/local/bin/scripts/init_system.sh ]; then
    . /usr/local/bin/scripts/init_system.sh
fi

export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

/usr/local/bin/scripts/init_audio.sh
/usr/local/bin/scripts/init_proton.sh
/usr/local/bin/scripts/init_sunshine.sh
/usr/local/bin/scripts/watchdog.sh &

# --- 4. SESSION LOOP ---
while true; do
    echo "--- [Session] Starting Graphics Stack ---"

    # A. CHECK MODE
    # Default to SDR if file doesn't exist
    DISPLAY_MODE="SDR"
    if [ -f "/home/steam/.config/display_mode" ]; then
        DISPLAY_MODE=$(cat /home/steam/.config/display_mode | tr -d '[:space:]')
    else
        # Force create the file so there is no ambiguity on first run
        echo -n "SDR" > /home/steam/.config/display_mode
        chown steam:steam /home/steam/.config/display_mode
    fi
    echo "    >>> DETECTED MODE: '$DISPLAY_MODE' <<<"

    # B. BUILD ARGUMENTS
    GS_ARGS=( "-e" "-W" "$WIDTH" "-H" "$HEIGHT" "-r" "$REFRESH" "--force-grab-cursor" )
    
    if [ "$DISPLAY_MODE" = "HDR" ]; then
        echo "    [Config] Applying HDR Flags..."
        GS_ARGS+=( "--hdr-enabled" "--hdr-itm-enable" )
    else
        echo "    [Config] Applying SDR Flags..."
        GS_ARGS+=( "--sdr-gamut-widen" )
    fi

    # C. START GAMESCOPE
    # We use 'runuser' to execute the wrapper script.
    # The '--' ensures Gamescope knows the script is the command to run.
    runuser -u steam -- gamescope "${GS_ARGS[@]}" -- /usr/local/bin/start_steam.sh &
    
    GS_PID=$!

    # D. WAIT FOR SOCKET
    echo "Waiting for Wayland socket..."
    TIMEOUT=30
    while [ ! -S "$XDG_RUNTIME_DIR/gamescope-0" ] && [ $TIMEOUT -gt 0 ]; do
        sleep 0.5
        ((TIMEOUT--))
    done
    
    # E. START SUNSHINE
    SUNSHINE_PID=""
    if [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then
        export WAYLAND_DISPLAY=gamescope-0
        chmod 777 $XDG_RUNTIME_DIR/gamescope-0
        
        echo "    Starting Sunshine..."
        export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
        export PULSE_SOURCE="sunshine-stereo.monitor"
        export PULSE_SINK="sunshine-stereo"
        export XDG_SEAT=seat0  
        export EGL_PLATFORM=wayland
        
        sunshine &
        SUNSHINE_PID=$!
    else
        echo "    [Error] Gamescope socket not found after 15s. Skipping Sunshine."
    fi

    # F. BLOCK UNTIL EXIT
    wait $GS_PID
    
    echo "--- [Session] Gamescope exited. Cleaning up for restart... ---"
    
    if [ ! -z "$SUNSHINE_PID" ]; then
        kill $SUNSHINE_PID 2>/dev/null || true
    fi
    killall -9 steam gamescope sunshine 2>/dev/null || true
    sleep 2
done
