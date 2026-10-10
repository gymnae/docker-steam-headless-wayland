#!/bin/bash
set -e

echo "--- [Audio] Initializing Audio Stack (High Priority / Nice) ---"

# Low latency: 256 frames @ 48 kHz = ~5.3ms per cycle (raise to 512 if audio crackles).
# Written as config drop-ins: env vars don't survive 'su - steam' (login shell resets env).
# 48 kHz fixed = Opus native rate, no resampling between games and Sunshine.
mkdir -p /etc/pipewire/pipewire.conf.d /etc/pipewire/pipewire-pulse.conf.d
cat > /etc/pipewire/pipewire.conf.d/10-sunshine.conf <<EOF
context.properties = {
    default.clock.rate          = 48000
    default.clock.allowed-rates = [ 48000 ]
    default.clock.quantum       = 256
    default.clock.min-quantum   = 256
    default.clock.max-quantum   = 1024
}
EOF
cat > /etc/pipewire/pipewire-pulse.conf.d/10-sunshine.conf <<EOF
pulse.properties = {
    pulse.min.req          = 256/48000
    pulse.default.req      = 256/48000
    pulse.min.quantum      = 256/48000
    pulse.default.format   = F32
}
EOF

# Cleanup
rm -rf $XDG_RUNTIME_DIR/pipewire-* $XDG_RUNTIME_DIR/pulse
rm -rf /home/steam/.local/state/wireplumber

# Permissions
mkdir -p /home/steam/.local/state/wireplumber
chown steam:steam /home/steam/.local/state/wireplumber
mkdir -p $XDG_RUNTIME_DIR/pulse
chown -R steam:steam $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR/pulse

# --------------------------------------------------------
# Helper Function: Start & Renice
# --------------------------------------------------------
start_and_nice() {
    NAME=$1
    CMD=$2
    
    echo "Starting $NAME..."
    # Start the process as 'steam'
    su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR; $CMD &"
    
    # Wait for PID creation
    sleep 1
    
    # Find PID owned by steam
    PID=$(pgrep -n -u steam $NAME)
    
    if [ -n "$PID" ]; then
        echo "  -> $NAME running at PID $PID"
        
        # Apply High Priority (Nice -15)
        # Since we are running this script as root, we can force this
        # without needing /etc/security/limits.conf edits.
        if renice -n -15 -p $PID >/dev/null 2>&1; then
            echo "  -> [OK] Priority boosted (Nice -15)"
            chrt -f -p 20 $PID >/dev/null 2>&1 || true
        else
            echo "  -> [Warn] Failed to boost priority"
        fi
    else
        echo "  -> [Error] $NAME failed to start!"
        exit 1
    fi
}

# 1. Start PipeWire Core
start_and_nice "pipewire" "pipewire"

# Wait for Socket
TIMEOUT=10
while [ ! -e "$XDG_RUNTIME_DIR/pipewire-0" ]; do
    if [ $TIMEOUT -le 0 ]; then echo "Error: PipeWire socket failed"; exit 1; fi
    sleep 1
    ((TIMEOUT--))
done

# 2. Start WirePlumber
start_and_nice "wireplumber" "wireplumber"

# 3. Start PipeWire-Pulse
start_and_nice "pipewire-pulse" "pipewire-pulse"

# Wait for Pulse Socket
TIMEOUT=10
while [ ! -S "$XDG_RUNTIME_DIR/pulse/native" ]; do
    if [ $TIMEOUT -le 0 ]; then echo "Error: Pulse socket failed"; exit 1; fi
    sleep 1
    ((TIMEOUT--))
done

chmod 777 $XDG_RUNTIME_DIR/pulse/native

# 4. Create Sink
echo "Configuring Sink..."
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl load-module module-null-sink sink_name=sunshine-stereo rate=48000 sink_properties=\"device.description=Sunshine_Stereo node.pause-on-idle=false\""

su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl set-default-sink sunshine-stereo"
