#!/bin/bash
set -e

# --- 0. CLEANUP ---
echo "--- [Boot] Cleaning up ---"
killall -9 -q sunshine Hyprland gamescope steam seatd pipewire wireplumber rtkit-daemon || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* /run/dbus/pid 2>/dev/null

# --- 1. RUNTIME ENV & PERMISSIONS ---
echo "--- [Boot] Setting Environment & Permissions ---"

WIDTH=${WIDTH:-1920}
HEIGHT=${HEIGHT:-1080}
REFRESH=${REFRESH:-60}

export XDG_RUNTIME_DIR=/run/user/1000
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
chown steam:steam "$XDG_RUNTIME_DIR"

echo "    Applying device permissions..."
for dev in /dev/dri/card* /dev/dri/renderD* /dev/uinput /dev/hidraw* /dev/uhid /dev/nvidia*; do
    [ -e "$dev" ] && chmod 666 "$dev"
done

[ ! -e /dev/uinput ] && mknod /dev/uinput c 10 223 && chmod 666 /dev/uinput
[ ! -e /dev/tty0 ] && mknod /dev/tty0 c 4 0 && chmod 666 /dev/tty0
[ ! -e /dev/tty1 ] && mknod /dev/tty1 c 4 1 && chmod 666 /dev/tty1

mkdir -p /home/steam/.config /home/steam/.steam /home/steam/.local/state
chown -R steam:steam /home/steam/.config /home/steam/.steam /home/steam/.local

# --- 3. RUN MODULES ---
[ -f /usr/local/bin/scripts/init_system.sh ] && . /usr/local/bin/scripts/init_system.sh

export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

for script in init_audio init_proton init_sunshine watchdog; do
    if [ -x "/usr/local/bin/scripts/${script}.sh" ]; then
        /usr/local/bin/scripts/${script}.sh
    fi
done

# --- 4. SESSION LOOP ---
while true; do
    echo "--- [Session] Starting Graphics Stack ---"
    rm -rf "$XDG_RUNTIME_DIR"/wayland-*

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

    # B. CONFIGURE HYPRLAND
    mkdir -p /home/steam/.config/hypr
    if [ "$DISPLAY_MODE" = "HDR" ]; then
        echo "    [Config] Applying HDR..."
        echo "monitor=,${WIDTH}x${HEIGHT}@${REFRESH},auto,1,bitdepth,10" > /home/steam/.config/hypr/monitor.conf
    else
        echo "monitor=,${WIDTH}x${HEIGHT}@${REFRESH},auto,1" > /home/steam/.config/hypr/monitor.conf
    fi
    
    if [ -f "/usr/local/bin/scripts/hyprland.conf" ]; then
        cp /usr/local/bin/scripts/hyprland.conf /home/steam/.config/hypr/hyprland.conf
    fi
    chown -R steam:steam /home/steam/.config/hypr

    export SDL_GAMECONTROLLERCONFIG="050000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
050000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000011810000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,
030000004c050000e60c000000000000,PS5 Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b2,y:b3,platform:Linux,"

    # C. START HYPRLAND (Using your original sudo -E invocation)
    echo "    Running Hyprland..."
    sudo -E -u steam HOME=/home/steam \
        XDG_SESSION_TYPE=wayland \
        XDG_CURRENT_DESKTOP=Hyprland \
        GBM_BACKEND=nvidia-drm \
        LIBVA_DRIVER_NAME=nvidia \
        __GLX_VENDOR_LIBRARY_NAME=nvidia \
        WLR_NO_HARDWARE_CURSORS=1 \
        SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLERCONFIG" \
        Hyprland &
    
    COMP_PID=$!

    # D. WAIT FOR SOCKET
    echo "    Waiting for Wayland socket..."
    TIMEOUT=30
    FOUND_SOCKET=""
    while [ $TIMEOUT -gt 0 ]; do
        if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then FOUND_SOCKET="wayland-0"; break; fi
        if [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then FOUND_SOCKET="wayland-1"; break; fi
        sleep 0.5
        ((TIMEOUT--))
    done
    
    SUNSHINE_PID=""
    if [ -n "$FOUND_SOCKET" ]; then
        export WAYLAND_DISPLAY=$FOUND_SOCKET
        export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
        chmod 777 "$XDG_RUNTIME_DIR/$FOUND_SOCKET"
        
        echo "    Starting Sunshine..."
        sunshine &
        SUNSHINE_PID=$!
    else
        echo "    [Error] Wayland socket not found. Restarting session."
        kill -9 $COMP_PID 2>/dev/null || true
        sleep 2
        continue
    fi

    # WATCHDOG: Your original Audio/Input Background Watchdog
    (
        LAST_COUNT=0
        while true; do
            NEW_COUNT=$(ls -1 /dev/input | wc -l)
            if [ "$NEW_COUNT" != "$LAST_COUNT" ]; then
                udevadm trigger --action=change --subsystem-match=input
                LAST_COUNT=$NEW_COUNT
            fi
            
            chmod 666 /dev/input/event* 2>/dev/null || true
            chmod 666 /dev/input/js* 2>/dev/null || true
            chmod 666 /dev/hidraw* 2>/dev/null || true
            chmod 666 /dev/uhid 2>/dev/null || true
            
            if su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl get-default-sink" | grep -qv "sunshine-stereo"; then
                su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && pactl set-default-sink sunshine-stereo" 2>/dev/null || true
            fi
            
            sleep 5
        done
    ) &
    WATCHDOG_PID=$!

    # F. BLOCK UNTIL EXIT
    wait $COMP_PID
    
    echo "--- [Session] Compositor exited. Cleaning up... ---"
    
    [ -n "$SUNSHINE_PID" ] && kill "$SUNSHINE_PID" 2>/dev/null || true
    [ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
    killall -9 -q steam Hyprland sunshine || true
    sleep 2
done