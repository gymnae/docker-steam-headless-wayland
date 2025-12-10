#!/bin/bash
set -e

echo "--- [Audio] Initializing Audio Stack ---"

# Settings
export PIPEWIRE_LATENCY="128/48000"
export PIPEWIRE_QUANTUM="128/48000"
export PIPEWIRE_MIN_QUANTUM="128/48000"
export PIPEWIRE_MAX_QUANTUM="128/48000"
export PIPEWIRE_RATE="48000"
export PIPEWIRE_RESAMPLE_QUALITY="4"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"

# Cleanup
rm -rf $XDG_RUNTIME_DIR/pipewire-* $XDG_RUNTIME_DIR/pulse
rm -rf /home/steam/.local/state/wireplumber
mkdir -p $XDG_RUNTIME_DIR/pulse
chown -R steam:steam $XDG_RUNTIME_DIR/pulse
chmod 700 $XDG_RUNTIME_DIR/pulse

# 1. Start Core (High Priority)
echo "Starting PipeWire Core..."
# FIX: Removed '--reset-env' so XDG_RUNTIME_DIR is preserved
nice -n -15 setpriv --reuid=1000 --regid=1000 --init-groups --inh-caps=-all -- /usr/bin/pipewire &

# Wait for Socket
TIMEOUT=10
while [ ! -e "$XDG_RUNTIME_DIR/pipewire-0" ]; do
    if [ $TIMEOUT -le 0 ]; then echo "Error: PipeWire socket failed"; exit 1; fi
    sleep 1
    ((TIMEOUT--))
done

# 2. Start WirePlumber
echo "Starting WirePlumber..."
nice -n -15 setpriv --reuid=1000 --regid=1000 --init-groups --inh-caps=-all -- /usr/bin/wireplumber &
sleep 2

# 3. Start PulseAudio Compat
echo "Starting PipeWire-Pulse..."
nice -n -15 setpriv --reuid=1000 --regid=1000 --init-groups --inh-caps=-all -- /usr/bin/pipewire-pulse &

# Wait for Pulse Socket
TIMEOUT=10
while [ ! -S "$XDG_RUNTIME_DIR/pulse/native" ]; do
    if [ $TIMEOUT -le 0 ]; then echo "Error: Pulse socket failed"; exit 1; fi
    sleep 1
    ((TIMEOUT--))
done

chmod 777 $XDG_RUNTIME_DIR/pulse/native 2>/dev/null || true

# 4. Create Sink (Standard priority is fine for pactl)
echo "Configuring Sink..."
su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl load-module module-null-sink sink_name=sunshine-stereo rate=48000 sink_properties=device.description=Sunshine_Stereo"

su - steam -c "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR && \
               pactl set-default-sink sunshine-stereo"
