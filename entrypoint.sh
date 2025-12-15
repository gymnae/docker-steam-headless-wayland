#!/bin/bash
set -e

# --- 0. CLEANUP ---
echo "--- [Boot] Cleaning up ---"
# Added -q to killall to suppress "no process found" noise
killall -9 -q sunshine gamescope steam seatd pipewire wireplumber rtkit-daemon || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* /run/dbus/pid 2>/dev/null

# --- 1. RUNTIME ENV & PERMISSIONS ---
echo "--- [Boot] Setting Environment & Permissions ---"

# Set defaults
WIDTH=${WIDTH:-2560}
HEIGHT=${HEIGHT:-1440}
REFRESH=${REFRESH:-60}

# Set vars
export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
chown steam:steam "$XDG_RUNTIME_DIR"

# Loop for cleaner permission setting
echo "    Applying device permissions..."
for dev in /dev/dri/card0 /dev/dri/renderD* /dev/uinput /dev/hidraw* /dev/uhid; do
    [ -e "$dev" ] && chmod 666 "$dev"
done

# Create nodes if missing
[ ! -e /dev/uinput ] && mknod /dev/uinput c 10 223 && chmod 666 /dev/uinput
[ ! -e /dev/tty0 ] && mknod /dev/tty0 c 4 0 && chmod 666 /dev/tty0
[ ! -e /dev/tty1 ] && mknod /dev/tty1 c 4 1 && chmod 666 /dev/tty1

# Fix Steam directories
mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config /home/steam/.steam /home/steam/.local

# --- 3. RUN MODULES ---
# Source init system if it exists
[ -f /usr/local/bin/scripts/init_system.sh ] && . /usr/local/bin/scripts/init_system.sh

export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# Execute helper scripts
for script in init_audio init_proton init_sunshine watchdog; do
    if [ -x "/usr/local/bin/scripts/${script}.sh" ]; then
        /usr/local/bin/scripts/${script}.sh
    fi
done

# --- 4. SESSION LOOP ---
while true; do
    echo "--- [Session] Starting Graphics Stack ---"

    # A. CHECK MODE
    DISPLAY_MODE="SDR"
    MODE_FILE="/home/steam/.config/display_mode"
    
    if [ -f "$MODE_FILE" ]; then
        DISPLAY_MODE=$(tr -d '[:space:]' < "$MODE_FILE")
    else
        echo -n "SDR" > "$MODE_FILE"
        chown steam:steam "$MODE_FILE"
    fi
    echo "    >>> DETECTED MODE: '$DISPLAY_MODE' <<<"

    # B. BUILD ARGUMENTS (FIXED)
    # Note: Every flag and every value is a separate array element.
    GS_ARGS=( 
	"-e" 
        "-f" 
	"-h" "$HEIGHT" 
        "-w" "$WIDTH" 
	"-W" "$WIDTH" 
        "-H" "$HEIGHT" 
        "-r" "$REFRESH" 
        "--force-grab-cursor" 
    )

    if [ "$DISPLAY_MODE" = "HDR" ]; then
        echo "    [Config] Applying HDR Flags..."
        GS_ARGS+=( "--hdr-enabled" "--hdr-itm-enable" )
    fi
    # REMOVED the 'else' block that wiped the array

    # C. START GAMESCOPE

    echo "    Running Gamescope..."
	export SDL_GAMECONTROLLERCONFIG="050000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
	050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
	030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,
	050000004c050000c405000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b3,y:b2,platform:Linux,"
    echo "DEBUG: Running gamescope with: ${GS_ARGS[*]}"    
    # We pass the array exactly as is using "${GS_ARGS[@]}"
    runuser -u steam -- gamescope "${GS_ARGS[@]}" -- steam -gamepadui -noverifyfiles &
    GS_PID=$!

    # D. WAIT FOR SOCKET
    echo "    Waiting for Wayland socket..."
    TIMEOUT=30
    while [ ! -S "$XDG_RUNTIME_DIR/gamescope-0" ] && [ $TIMEOUT -gt 0 ]; do
        sleep 0.5
        ((TIMEOUT--))
    done
    
    # E. START SUNSHINE
    SUNSHINE_PID=""
    if [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then
        # Export vars explicitly for Sunshine context
        export WAYLAND_DISPLAY=gamescope-0
        export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
        
        # Ensure permissions so Sunshine can read the socket
        chmod 770 "$XDG_RUNTIME_DIR/gamescope-0"
        
        echo "    Starting Sunshine..."
        sunshine &
        SUNSHINE_PID=$!
    else
        echo "    [Error] Gamescope socket not found after 15s. Skipping Sunshine."
    fi

    # F. BLOCK UNTIL EXIT
    wait $GS_PID
    
    echo "--- [Session] Gamescope exited. Cleaning up... ---"
    
    [ -n "$SUNSHINE_PID" ] && kill "$SUNSHINE_PID" 2>/dev/null || true
    killall -9 -q steam gamescope sunshine || true
    sleep 2
done
