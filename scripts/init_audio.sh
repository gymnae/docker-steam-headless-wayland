#!/bin/bash
set -e

echo "--- [Audio] Initializing Audio Stack (High Priority / Nice) ---"

# 1. Clean up old sockets
rm -rf /run/user/1000/pulse
mkdir -p /run/user/1000/pulse

# 2. Configure PipeWire Context
# We explicitly set the default clock rate and allowed quantum range.
# This prevents the "crackling" or "silence" when games request weird buffer sizes.
mkdir -p /home/steam/.config/pipewire/pipewire.conf.d
cat > /home/steam/.config/pipewire/pipewire.conf.d/99-rates.conf <<EOF
context.properties = {
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 48000 ]
    default.clock.min-quantum = 128
    default.clock.max-quantum = 2048
}
EOF

# 3. Start PipeWire
# Run with high priority to prevent dropouts
nice -n -15 pipewire &
sleep 1

# 4. Start WirePlumber (Session Manager)
nice -n -15 wireplumber &
sleep 1

# 5. Start PipeWire-Pulse (The PulseAudio Server)
# This is what the game actually talks to.
nice -n -15 pipewire-pulse &
sleep 1

echo "    -> Audio Stack Started."
