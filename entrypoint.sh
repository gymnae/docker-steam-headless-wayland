#!/bin/bash
set -e

# --- 0. TEARDOWN ON BOOT ---
echo "--- [Boot] Cleaning up ---"
killall -9 -q sunshine gamescope steam seatd pipewire wireplumber rtkit-daemon || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* /run/dbus/pid /tmp/trigger_restart 2>/dev/null

# --- 1. RUNTIME ENV ---
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_SEAT=seat0
export SEATD_VTBOUND=0
export LIBSEAT_BACKEND=seatd

mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
chown steam:steam "$XDG_RUNTIME_DIR"

# Global Permissions
chmod 666 /dev/uinput /dev/dri/card0 /dev/dri/renderD* /dev/input/event* 2>/dev/null || true
chown root:video /dev/input/event* 2>/dev/null || true

# --- 2. INIT MODULES ---
for script in init_system init_audio init_proton init_sunshine; do
    if [ -x "/usr/local/bin/scripts/${script}.sh" ]; then
        /usr/local/bin/scripts/${script}.sh
    fi
done

# --- 3. SESSION LOOP ---
while true; do
    echo "--- [Session] Starting Graphics Stack ---"
    
    # ----------------------------------------
    # PHASE 1: TEARDOWN
    # ----------------------------------------
    rm -f /tmp/trigger_restart
    unset WAYLAND_DISPLAY
    unset DISPLAY
    
    killall -q sunshine gamescope steam seatd || true
    sleep 1
    killall -9 -q sunshine gamescope steam seatd || true
    
    rm -rf /tmp/.X11-unix /tmp/.X0-lock /run/seatd.sock "$XDG_RUNTIME_DIR/gamescope-0"
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix

    # ----------------------------------------
    # PHASE 2: HARDWARE SETUP
    # ----------------------------------------
    udevadm trigger --action=change --subsystem-match=input
    udevadm trigger --action=change --subsystem-match=drm
    sleep 0.5

    echo "    Starting seatd..."
    seatd -g video &
    SEATD_PID=$!
    
    # Wait for socket
    TIMEOUT=10
    while [ ! -S "/run/seatd.sock" ]; do
        sleep 0.1
        ((TIMEOUT--))
        if [ $TIMEOUT -le 0 ]; then echo "Seatd failed to start"; break; fi
    done
    chmod 777 /run/seatd.sock

    # ----------------------------------------
    # PHASE 3: CONFIGURATION
    # ----------------------------------------
    CURRENT_WIDTH=1920
    CURRENT_HEIGHT=1080
    CURRENT_REFRESH=60
    CURRENT_HDR="false"
    
    CONFIG_FILE="/home/steam/.config/display_config"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        CURRENT_WIDTH=${WIDTH:-$CURRENT_WIDTH}
        CURRENT_HEIGHT=${HEIGHT:-$CURRENT_HEIGHT}
        CURRENT_REFRESH=${REFRESH:-$CURRENT_REFRESH}
        CURRENT_HDR=${HDR_ENABLED:-$CURRENT_HDR}
    fi

    echo "    >>> CONFIG: ${CURRENT_WIDTH}x${CURRENT_HEIGHT} @ ${CURRENT_REFRESH} (HDR: $CURRENT_HDR) <<<"

    GS_ARGS="-e -f -w $CURRENT_WIDTH -h $CURRENT_HEIGHT -W $CURRENT_WIDTH -H $CURRENT_HEIGHT -r $CURRENT_REFRESH --force-grab-cursor"

    if [ "$CURRENT_HDR" = "true" ] || [ "$CURRENT_HDR" = "1" ]; then
        GS_ARGS="$GS_ARGS --hdr-enabled --hdr-itm-enable"
    else
        GS_ARGS="$GS_ARGS --sdr-gamut-wideness 0"
    fi
    
    # ----------------------------------------
    # PHASE 4: LAUNCH
    # ----------------------------------------
    
    echo "    Launching Gamescope..."
    
    # Use runuser with split groups to fix syntax error
    runuser -u steam -g steam -G video -G input -G audio -G render -- /bin/bash -c "
        export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
        export GAMESCOPE_WIDTH=$CURRENT_WIDTH
        export GAMESCOPE_HEIGHT=$CURRENT_HEIGHT
        export WLR_BACKENDS=headless
        export UG_MAX_BUFFERS=256
        exec gamescope $GS_ARGS -- steam -gamepadui -noverifyfiles -fulldesktopres
    " &
    
    GS_PID=$!

    echo "    Waiting for Wayland socket..."
    TIMEOUT=30
    while [ ! -S "$XDG_RUNTIME_DIR/gamescope-0" ] && [ $TIMEOUT -gt 0 ]; do
        sleep 0.5
        ((TIMEOUT--))
    done

    if [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then
        export WAYLAND_DISPLAY=gamescope-0
        export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
        chmod 777 "$XDG_RUNTIME_DIR/gamescope-0"
        
        echo "    Starting Sunshine..."
        sunshine &
        SUNSHINE_PID=$!
    else
        echo "    [Error] Gamescope failed to start (Socket missing)."
    fi

    # ----------------------------------------
    # PHASE 5: WATCHDOG
    # ----------------------------------------
    while kill -0 "$GS_PID" 2>/dev/null; do
        if [ -f "/tmp/trigger_restart" ]; then
            echo "    >>> RESTART TRIGGER DETECTED <<<"
            break
        fi
        sleep 0.5
    done
    
    echo "--- [Session] Stopping services... ---"
    
    [ -n "$SUNSHINE_PID" ] && kill "$SUNSHINE_PID" 2>/dev/null || true
    killall -9 -q steam || true
    
    if kill -0 "$GS_PID" 2>/dev/null; then
        kill "$GS_PID"
        TIMEOUT=5
        while kill -0 "$GS_PID" 2>/dev/null && [ $TIMEOUT -gt 0 ]; do sleep 0.5; ((TIMEOUT--)); done
        kill -9 "$GS_PID" 2>/dev/null || true
    fi
    
    sleep 1
done
