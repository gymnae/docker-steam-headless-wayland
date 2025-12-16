#!/bin/bash
set -e

# --- 0. BOOT CLEANUP ---
echo "--- [Boot] Cleaning up ---"
killall -9 -q sunshine gamescope steam seatd pipewire wireplumber rtkit-daemon || true
rm -rf /tmp/.X* /run/user/1000/* /run/seatd.sock /tmp/pulse-* /run/dbus/pid /tmp/trigger_restart 2>/dev/null

# --- 1. RUNTIME ENV ---
# CRITICAL FIX: These variables tell seatd to ignore physical terminals
export SEATD_VTBOUND=0
export LIBSEAT_BACKEND=seatd

export XDG_RUNTIME_DIR=/run/user/1000
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

# --- 3. SUPERVISOR LOOP ---
while true; do
    echo "--- [Supervisor] Starting Session ---"
    
    # ----------------------------------------
    # PHASE A: TEARDOWN
    # ----------------------------------------
    rm -f /tmp/trigger_restart
    
    # Kill previous session
    killall -q sunshine gamescope steam seatd || true
    sleep 1
    killall -9 -q sunshine gamescope steam seatd || true
    
    # Socket Cleanup
    rm -rf /tmp/.X11-unix /tmp/.X0-lock /run/seatd.sock "$XDG_RUNTIME_DIR/gamescope-0"
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix

    # ----------------------------------------
    # PHASE B: HARDWARE PREP
    # ----------------------------------------
    udevadm trigger --action=change --subsystem-match=input
    udevadm trigger --action=change --subsystem-match=drm
    sleep 0.5

    # Start Seatd (Root Service)
    echo "    [Supervisor] Starting seatd..."
    seatd -g video &
    SEATD_PID=$!
    
    # Wait for seatd socket
    TIMEOUT=10
    while [ ! -S "/run/seatd.sock" ]; do
        sleep 0.1
        ((TIMEOUT--))
        if [ $TIMEOUT -le 0 ]; then echo "Seatd failed to start"; break; fi
    done
    chmod 777 /run/seatd.sock

    # ----------------------------------------
    # PHASE C: LAUNCH USER SESSION
    # ----------------------------------------
    echo "    [Supervisor] Launching Steam Session..."
    # Run the session script as steam user
    runuser -u steam -g steam -G video -G input -G audio -G render -- /usr/local/bin/scripts/steam-session.sh &
    SESSION_PID=$!

    # ----------------------------------------
    # PHASE D: SUNSHINE & WATCHDOG
    # ----------------------------------------
    
    # Wait for Gamescope socket
    TIMEOUT=30
    while [ ! -S "$XDG_RUNTIME_DIR/gamescope-0" ] && [ $TIMEOUT -gt 0 ]; do
        sleep 0.5
        ((TIMEOUT--))
    done

    # Start Sunshine
    if [ -S "$XDG_RUNTIME_DIR/gamescope-0" ]; then
        # Exports for Sunshine
        export WAYLAND_DISPLAY=gamescope-0
        export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
        chmod 777 "$XDG_RUNTIME_DIR/gamescope-0"
        
        echo "    [Supervisor] Starting Sunshine..."
        sunshine &
        SUNSHINE_PID=$!
    else
        echo "    [Supervisor] Error: Gamescope socket not found."
    fi

    # WATCHDOG LOOP
    while kill -0 "$SESSION_PID" 2>/dev/null; do
        if [ -f "/tmp/trigger_restart" ]; then
            echo "    >>> RESTART TRIGGER DETECTED <<<"
            break
        fi
        sleep 0.5
    done
    
    echo "--- [Supervisor] Session Ending... ---"
    
    # Graceful Shutdown
    [ -n "$SUNSHINE_PID" ] && kill "$SUNSHINE_PID" 2>/dev/null || true
    killall -9 -q steam || true
    
    if kill -0 "$SESSION_PID" 2>/dev/null; then
        kill "$SESSION_PID"
        TIMEOUT=5
        while kill -0 "$SESSION_PID" 2>/dev/null && [ $TIMEOUT -gt 0 ]; do sleep 0.5; ((TIMEOUT--)); done
        kill -9 "$SESSION_PID" 2>/dev/null || true
    fi
    
    sleep 1
done
