#!/bin/bash
set -e

echo "--- [Sunshine] Configuring ---"

mkdir -p /home/steam/.config/sunshine
CONF_FILE="/home/steam/.config/sunshine/sunshine.conf"

if [ -f "$CONF_FILE" ]; then
    echo "✅ Found existing config."
else
    echo "⚠️  Creating default config..."
    cat > "$CONF_FILE" <<EOF
[general]
address = 0.0.0.0
upnp = disabled
gamepad = auto
[video]
capture = kms
encoder = nvenc
EOF
fi
chown steam:steam "$CONF_FILE"

# Link for Root
mkdir -p /root/.config
ln -sfn /home/steam/.config/sunshine /root/.config/sunshine

# Pulse Cookie
if [ -f /home/steam/.config/pulse/cookie ]; then
    mkdir -p /root/.config/pulse
    cp /home/steam/.config/pulse/cookie /root/.config/pulse/cookie
fi
